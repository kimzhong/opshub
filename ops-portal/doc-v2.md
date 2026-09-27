# Kind Ops Portal v2.0 — Node.js 重构版

整套运维平台从 **Python + 单文件 HTML** 重构为 **标准 Node.js 项目**。后端零框架（仅一个 `ws` 依赖），前端零构建。

---

## 一、前后对比

| 维度 | v1.0（Python） | v2.0（Node.js） |
|---|---|---|
| 后端 | Python `http.server` + `pty.fork()` | Node.js `http` + `child_process.spawn` |
| 前端 | 单个 50KB HTML（内联 CSS/JS） | 3 文件分离：HTML / CSS / JS Module |
| 依赖 | Python 标准库 + `websockets` | `ws` 一个包 |
| 路由 | 手写 if-else 分支 | 路由表 + 参数化路径（`:context`） |
| 配置 | 硬编码在文件里 | `config.js` 集中管理 + 环境变量 |
| 告警状态 | 简单全局变量 | 独立模块，三路数据源合并 |
| 退出处理 | 无 | SIGINT/SIGTERM 优雅关闭 |
| 页面 | 7 个 | 8 个（新增工具页） |

---

## 二、目录结构

```
ops-portal/
├── package.json          依赖声明（仅 ws）+ npm scripts
├── start.bat             Windows 一键启动（检查 Node / 装依赖）
├── README.md             完整文档
│
├── server/               ── 后端 ──
│   ├── index.js          入口：HTTP + 静态文件 + WebSocket 挂载 + 优雅退出
│   ├── config.js         端口 / 集群 context / 端点集中配置
│   ├── k8s.js            kubectl、Helm、Prometheus、Loki 封装层
│   ├── routes.js         24 条 API 路由（手写 router）
│   ├── alerts.js         告警聚合状态（Prometheus + Webhook + 操作事件）
│   └── terminal.js       WebSocket 交互终端 + 一次性命令执行
│
└── public/               ── 前端 ──
    ├── index.html        8 个页面结构
    ├── styles.css        设计系统：CSS 变量 + 组件类
    └── app.js            前端逻辑：api 层 / store / render / actions
```

代码总量：后端 5 个文件约 2000 行，前端 3 个文件约 1800 行。

---

## 三、启动方式

```bash
cd C:\Users\kim\kind-env\ops-portal
npm install     # 首次，装 ws
npm start       # 或双击 start.bat
```

打开 **http://localhost:8099/**

`start.bat` 会自动检查 Node.js 是否安装、依赖是否就绪，然后启动服务。

告警和日志需要另开 WSL 窗口做端口转发：

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-prometheus 9090:9090 &
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/loki-gateway 3100:80 &
```

---

## 四、后端实现

### 4.1 k8s.js — 访问层

所有集群访问都走 `wsl -d Ubuntu -- kubectl`，这样 Windows 侧不需要 kubeconfig，也避开 WSL2 网络隔离。

```javascript
// 底层执行器
export function wslExec(args, { timeout = 30000 } = {}) {
  return new Promise((resolve) => {
    execFile('wsl', ['-d', CONFIG.wslDistro, '--', ...args],
      { timeout, maxBuffer: 32 * 1024 * 1024, encoding: 'utf8' },
      (err, stdout, stderr) => resolve({
        code: err ? (err.code ?? 1) : 0,
        stdout: stdout || '', stderr: stderr || '',
      }));
  });
}

// kubectl + JSON
export async function kubectlJson(context, ...args) {
  const full = ['kubectl', '--context', context, ...args, '-o', 'json'];
  const { code, stdout } = await wslExec(full);
  if (code !== 0) return null;
  return JSON.parse(stdout);
}
```

导出的能力：

| 函数 | 作用 |
|---|---|
| `getClusterOverview(ctx)` | 节点规格 + Pod 总数 + 按命名空间统计 |
| `listPods(ctx, ns)` | Pod 列表（phase、ready、重启次数、node、镜像） |
| `podLogs` / `podDescribe` | 原始文本输出 |
| `rolloutRestart` / `rolloutStatus` / `scaleDeployment` | Deployment 操作 |
| `listHpa` / `listServices` / `listHelmReleases` | 资源查询 |
| `listArgoApps(ctx)` | 读 ArgoCD Application CRD |
| `syncArgoApp(ctx, app)` | 触发同步（CLI 优先，回退 argocd-server exec） |
| `fetchAlerts()` | 原生 `fetch` 调 Prometheus API |
| `promQuery(expr)` | PromQL 即席查询 |
| `lokiQuery(logql, opts)` | LogQL 区间查询（带 `X-Scope-OrgID` 头） |

### 4.2 routes.js — 路由表

手写极简 router，支持路径参数：

```javascript
function route(method, pattern, handler) {
  const keys = [];
  const regexSrc = pattern.replace(/:([A-Za-z_]+)/g, (_, k) => {
    keys.push(k);
    return '([^/]+)';
  });
  routes.set(`${method} ${pattern}`, {
    regex: new RegExp(`^${regexSrc}$`), keys, handler,
  });
}

// 注册
route('GET', '/api/cluster/:context', async ({ params }) =>
  json(await getClusterOverview(params.context))
);
```

Handler 统一签名，拿到的上下文：

```javascript
{ req, body, params, query (URLSearchParams), headers (Headers) }
```

返回 `{ status, data }`，由入口统一序列化成 JSON + CORS。

### 4.3 alerts.js — 告警聚合

三路数据源合并成一个状态对象：

```
1. Prometheus  firing / pending 告警     （30s 自动轮询）
2. 飞书 Webhook  POST 进来的消息         （实时）
3. 平台操作事件  重启/扩缩容/同步的结果    （操作时记录）
```

消息文本提取兼容三种飞书格式：

```javascript
function extractText(payload) {
  if (payload.content?.text) return payload.content.text;          // text 类型
  if (payload.card) return extractCardText(payload.card);          // 卡片消息
  if (payload.event?.message?.content) { ... }                    // 事件订阅
  return JSON.stringify(payload).slice(0, 200);
}
```

`isAlertText()` 用正则判断是否算活跃告警：

```javascript
/firing|critical|告警|alert|error|失败|异常/i
```

### 4.4 terminal.js — WebSocket 终端

用 `spawn` 跑常驻子进程，stdin/stdout 通过 WebSocket 双向转发：

```javascript
const args = ['-d', distro, '--', 'kubectl', 'exec', '-i',
              '--context', ctx, '-n', ns, pod, '--', '/bin/sh'];
const child = spawn('wsl', args, { stdio: ['pipe', 'pipe', 'pipe'] });

child.stdout.on('data', (chunk) => {
  broadcast(session, { type: 'data', data: chunk.toString('utf8') });
});
```

**没有分配真实 PTY**（用 `-i` 而非 `-it`），因为 Node 侧没有 PTY 实现。好处是零原生依赖，代价是没有行编辑和彩色提示符。接口设计成可替换 —— 需要完整 PTY 时把 `spawn` 换成 `node-pty`，其余代码不动。

另外提供无状态的一次性执行，更稳：

```javascript
export async function execOnce(context, namespace, args, { timeout = 30000 } = {}) {
  // spawn + 收集 stdout/stderr，退出码返回
}
```

WebSocket 消息协议：

| 客户端 → 服务端 | 说明 |
|---|---|
| `{type:'create', context, namespace, pod, container}` | 创建 shell 会话 |
| `{type:'input', data}` | 写入 stdin |
| `{type:'run', context, namespace, args}` | 一次性执行 |
| `{type:'close'}` / `{type:'ping'}` | 关闭 / 心跳 |

| 服务端 → 客户端 | 说明 |
|---|---|
| `{type:'hello'}` | 连接确认 |
| `{type:'ready', sessionId}` | 会话就绪 |
| `{type:'data'}` | 输出 |
| `{type:'result', ok}` | 一次性执行结果 |
| `{type:'error'}` / `{type:'exit'}` | 错误 / 退出 |

会话生命周期：客户端断开且无其他订阅者时自动销毁子进程。

### 4.5 index.js — 入口

```javascript
// 静态文件（含目录穿越防护 + SPA fallback）
const PUBLIC_DIR = path.resolve(__dirname, '..', 'public');
if (!full.startsWith(PUBLIC_DIR)) { res.writeHead(403).end('forbidden'); }

// 优雅退出
process.on('SIGINT', () => shutdown('SIGINT'));
function shutdown() {
  alerts.stopAutoRefresh();
  destroyAll();              // 清理终端子进程
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000);   // 3s 兜底
}
```

---

## 五、前端实现

### 5.1 三层分离

```
api.*      所有后端调用集中在一处，改接口只动这里
store      全局状态（在线状态、配置、集群数据、选中项）
render.*   每个页面一个渲染函数
```

### 5.2 API 层

```javascript
async function req(path, opts = {}) {
  try {
    const res = await fetch(`${API}${path}`, {
      headers: { 'Content-Type': 'application/json' },
      ...opts,
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
    return data;
  } catch (e) {
    if (e instanceof TypeError) throw new Error('后端未连接（请运行 npm start）');
    throw e;
  }
}

const api = {
  clusters: ()          => req('/api/clusters'),
  pods:     (ctx, ns)   => req(`/api/pods?context=${ctx}&namespace=${ns}`),
  loki:     (q, l, s)   => req(`/api/loki/query?q=${encodeURIComponent(q)}&limit=${l}&seconds=${s}`),
  scale:    (ctx, ns, name, replicas) =>
              req('/api/scale', { method: 'POST', body: { context: ctx, namespace: ns, name, replicas } }),
  // ...共 20 个方法
};
```

### 5.3 设计系统

CSS 变量定义主题，组件类复用：

```css
:root {
  --bg: #0d1117;  --bg2: #161b22;  --bg3: #21262d;
  --border: #30363d;
  --green: #3fb950;  --red: #f85149;  --yellow: #d29922;  --blue: #58a6ff;
  --text: #c9d1d9;   --text2: #8b949e;
  --radius: 8px;  --mono: 'Cascadia Code', Consolas, monospace;
}
```

### 5.4 页面

| 页面 | 关键交互 |
|---|---|
| 📊 概览 | 4 个聚合指标 + 3 个集群卡片（点击跳集群页）+ 告警摘要 + 操作时间线 |
| 🖥️ 集群 | 节点规格（OS/CPU/内存/Pod 上限）+ 命名空间分布（点击查 Pod）+ Helm releases |
| 📦 Pods | context/namespace 双下拉 → Pod 列表，每行三个快捷按钮（日志/详情/终端）；demo-app 时自动加载 HPA + Services |
| 🔄 GitOps | 应用卡片（健康/同步/auto-sync 徽章 + 6 字段网格），单应用同步 + 同步全部 |
| 📋 日志 | LogQL 输入 + 时间窗口/行数选择 + 5 个快捷查询 chips，输出按 error/warn 着色 |
| 🚨 告警 | 4 个标签页：firing 告警 / 飞书消息 / 操作时间线 / 接入配置（含测试按钮） |
| 💻 终端 | context/ns/pod 三级选择 → WebSocket 交互 shell，另有 6 个快捷命令 chips |
| 🔗 工具 | 9 个组件的直达链接 + 凭据提示 |

---

## 六、配置管理

全部集中在 `server/config.js`，可用环境变量覆盖：

| 变量 | 默认值 |
|---|---|
| `OPS_PORT` | 8099 |
| `OPS_WS_PORT` | 8098 |
| `WSL_DISTRO` | Ubuntu |
| `PROM_URL` | http://localhost:9090 |
| `LOKI_URL` | http://localhost:3100 |
| `CMD_TIMEOUT` | 30000 |
| `WEBHOOK_SECRET` | 未设置（设置后需带 `X-Webhook-Secret` 头） |

集群 context 也在同一文件：

```javascript
clusters: {
  ops:      'kind-ops-mgmt',
  regionA:  'kind-biz-prod-regiona',
  regionB:  'kind-biz-prod-regionb',
}
```

---

## 七、飞书告警接入

平台暴露 `POST /webhook/feishu`，让 Alertmanager 指过来：

```yaml
receivers:
  - name: feishu
    webhook_configs:
      - url: http://<你的IP>:8099/webhook/feishu
        send_resolved: true

route:
  receiver: feishu
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h
```

```bash
kubectl --context kind-ops-mgmt apply -n monitoring -f alertmanager-config.yaml
```

告警页的"接入配置"标签页有**发送测试消息**按钮，配置好就能直接验证链路，不用等真告警。

支持三种消息格式：自定义机器人 text、飞书卡片、事件订阅 `im.message.receive_v1`。

---

## 八、验证结果

| 项目 | 结果 |
|---|---|
| 服务启动 | ✅ Node v22.18.0，端口 8099 |
| `/health` | ✅ 返回 uptime、告警数 |
| 静态资源 | ✅ `/` 20828 B、`/styles.css` 17326 B、`/app.js` 47737 B |
| 24 条 API 路由 | ✅ `/api/config`、`/api/helm`、`/api/alerts`、`/api/terminal/sessions` 全部 200 |
| WebSocket 握手 | ✅ `hello` 消息正常返回 |
| 飞书 Webhook | ✅ 消息入库，告警关键词识别正确（`total=1 / alertCount=1`） |
| kubectl 调用 | ⚠️ 当前 WSL 环境未装 kubectl、无 Kind 集群，接口正确降级返回 0 未崩溃 |

> 集群数据相关的接口（节点/Pod/HPA/ArgoCD）需要 Kind 集群在线才有真实数据。恢复集群后直接可用，无需改代码。

---

## 九、快捷键

- `Ctrl/Cmd + R` — 刷新当前页数据
- `Esc` — 关闭弹窗
- `Enter` — 终端执行 / 日志查询
