# Kind 多集群运维平台 v2.0 — 功能手册

## 文件位置

所有文件位于 `C:\Users\kim\kind-env\ops-portal\`

| 文件 | 作用 | 大小 |
|---|---|---|
| `index.html` | 运维平台主页面（浏览器直接打开） | 50KB |
| `proxy_server.py` | Python 代理服务（连接 K8s 集群） | 25KB |
| `start-proxy.bat` | Windows 一键启动器 | <1KB |

---

## 整体架构

```
Windows 浏览器
     │
     │  http://localhost:8099/
     ▼
proxy_server.py  (Python，常驻进程)
     │
     ├─→ WSL kubectl ──→ Kind 集群（3个集群）
     ├─→ curl ──→ Prometheus (localhost:9090)
     ├─→ curl ──→ Loki (localhost:3100)
     └─→ WebSocket ──→ kubectl exec PTY（终端）
```

---

## 一、启动步骤

### 第一步：确认集群在线

打开 WSL 终端，执行：

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
```

确认看到 4 个节点（1 个 control-plane + 3 个 worker）状态为 Ready。

### 第二步：启动代理服务

**方式 A — 直接运行（推荐）**

```bash
wsl -d Ubuntu
cd /mnt/c/Users/kim/kind-env/ops-portal
pip install websockets
python3 proxy_server.py
```

看到以下输出说明启动成功：
```
🚀 ops-portal 代理服务启动
   HTTP API:   http://localhost:8099
   Web SSH:    ws://localhost:8098
```

**方式 B — 双击启动（无需打开 WSL 终端）**

直接双击文件：
```
C:\Users\kim\kind-env\ops-portal\start-proxy.bat
```

> 注意：方式 B 会打开一个 PowerShell 窗口，保持窗口开着即为服务运行中。

### 第三步：启动集群端口转发（另一个 WSL 终端）

再打开一个 WSL 终端窗口，运行：

```bash
# Prometheus API（供告警页使用）
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-prometheus 9090:9090 &

# Loki 日志查询（供日志页使用）
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/loki-gateway 3100:80 &
```

### 第四步：打开平台

Windows 浏览器访问：**http://localhost:8099/**

看到以下内容说明全部就绪：
- 顶部 "代理在线" 绿色标签
- 3 个集群节点状态卡片（概览页）
- ArgoCD / Prometheus / Loki 数据

---

## 二、文件详解

### index.html — 平台前端

**位置**：`C:\Users\kim\kind-env\ops-portal\index.html`

**实现方式**：纯静态 HTML + CSS + JavaScript，无需构建，无需安装。

**页面结构**：

```
📊 概览     — 3集群聚合数据（节点/告警/应用数）
🖥️ 集群    — 实时 Pod 列表（选择 context + namespace）
🔄 GitOps   — ArgoCD 应用 + 6个快速操作
📋 日志     — Loki 查询输入框
🚨 告警     — Prometheus 告警 + Alertmanager 状态
💻 终端     — Web SSH（kubectl exec）
⚡ 快捷     — 12个一键入口
```

**API 调用方式**（JavaScript fetch）：

```javascript
// 获取 3 集群概览
fetch('http://localhost:8099/api/clusters')
  .then(r => r.json())
  .then(d => { /* d.clusters[].nodes[].ready */ });

// 获取 Pod 列表
fetch('http://localhost:8099/api/pods?context=kind-ops-mgmt&namespace=demo-app')
  .then(r => r.json())
  .then(d => { /* d.pods[].name, d.pods[].phase */ });

// 滚动重启
fetch('http://localhost:8099/api/rollout-restart', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    context: 'kind-ops-mgmt',
    namespace: 'demo-app',
    resource: 'deployment',
    name: 'demo-app'
  })
});

// Loki 查询
fetch('http://localhost:8099/api/loki?q={namespace="demo-app"}&limit=100')
  .then(r => r.json())
  .then(d => { /* d.streams[].line */ });
```

---

### proxy_server.py — 代理服务

**位置**：`C:\Users\kim\kind-env\ops-portal\proxy_server.py`

**依赖**：
```bash
pip install websockets   # Web SSH 终端需要
# 其他均为 Python 3 内置库（json, subprocess, http.server 等）
```

**核心逻辑**：

```python
# 1. kubectl 封装 — 执行 WSL 中的 kubectl 命令
def kubectl(ctx, *args, json_out=True):
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return json.loads(result.stdout)   # 返回 JSON

# 2. 集群概览 — 获取节点 + Pod 统计
def get_cluster_overview(ctx):
    nodes = kubectl(ctx, 'get', 'nodes')
    pods   = kubectl(ctx, 'get', 'pods', '--all-namespaces')
    # 解析 conditions 判断 Ready
    # 按 namespace 统计 Pod Running 数量
    return {'nodes': [...], 'total_pods': N, ...}

# 3. ArgoCD 应用 — 读取 CRD
def get_argocd_apps(ctx):
    result = kubectl(ctx, 'get', 'applications', '-n', 'argocd')
    # status.health.status / status.sync.status
    return [{'name': 'demo-app', 'health': 'Healthy', 'sync': 'Synced'}]

# 4. Loki 查询 — curl 访问 port-forward 的 Loki gateway
def loki_query(query, limit=100):
    cmd = ['curl', '-s', f'http://localhost:3100/loki/api/v1/query_range?query={q}&limit={limit}']
    return json.loads(subprocess.run(...).stdout)

# 5. Web SSH — pty.fork() + kubectl exec -it
class SSHChannel:
    def open(self):
        self.pid, self.master_fd = pty.fork()
        if self.pid == 0:
            os.execvp('wsl', ['wsl', '-d', 'Ubuntu', '--',
                              'kubectl', 'exec', '-it', self.pod, '--', '/bin/bash'])
```

**HTTP 路由**（BaseHTTPRequestHandler）：

```python
GET  /api/clusters           → 3集群概览
GET  /api/pods               → Pod 列表（?context=X&namespace=Y）
GET  /api/argocd/apps        → ArgoCD 应用
GET  /api/alerts             → Prometheus firing 告警
GET  /api/loki               → Loki 查询结果（?q=X）
GET  /api/logs               → kubectl logs（?pod=X&namespace=Y）
GET  /api/describe            → kubectl describe pod
GET  /api/terminal           → WebSocket 端点信息
POST /api/rollout-restart     → kubectl rollout restart
POST /api/scale               → kubectl scale --replicas=N
POST /api/argocd/sync         → ArgoCD app sync
POST /webhook/feishu          → 飞书告警 Webhook 接收
```

**WebSocket 终端**（WebSocket + PTY）：

```python
# 浏览器端
termWs = new WebSocket('ws://localhost:8098/ws/ssh?ctx=kind-ops-mgmt&ns=demo-app&pod=demo-app-xxx')

termWs.onmessage = (evt) => {
  const m = JSON.parse(evt.data)
  if (m.type === 'data') appendTerm(m.data)  // 输出到 textarea
}

termWs.onclose = () => { appendTerm('连接已关闭') }

// 发送命令
termWs.send(JSON.stringify({type: 'input', data: 'kubectl get nodes\r'}))
```

---

### start-proxy.bat — Windows 启动器

**位置**：`C:\Users\kim\kind-env\ops-portal\start-proxy.bat`

```batch
@echo off
cd /d C:\Users\kim\kind-env\ops-portal
echo ==========================================
echo  ops-portal 代理服务
echo  API: http://localhost:8099
echo ==========================================
python3 proxy_server.py
pause
```

**使用方法**：双击运行，保持窗口开着。关闭窗口 = 服务停止。

---

## 三、飞书告警接入

### 原理

```
Prometheus Alertmanager
       │
       ▼ 触发告警时 POST 到 Webhook
proxy_server.py /webhook/feishu
       │
       ▼ 可选：转发到飞书群
飞书群机器人 Webhook
```

### 配置步骤

1. 飞书群 → 设置 → 群机器人 → 添加自定义机器人
2. 复制 Webhook URL（格式：`https://open.feishu.cn/open-apis/bot/v2/hook/xxx`）
3. 在 `proxy_server.py` 中填入（或运行时传入）：

```python
# proxy_server.py 第 20 行附近
FEISHU_WEBHOOK_URL = "https://open.feishu.cn/open-apis/bot/v2/hook/你的webhook"
```

4. Alertmanager 配置（`C:\Users\kim\kind-env\demo-app\alertmanager-config.yaml`）已包含 Webhook receiver，apply 后生效：

```bash
kubectl --context kind-ops-mgmt apply -n monitoring \
  -f C:\Users\kim\kind-env\demo-app\alertmanager-config.yaml
```

### 测试告警

```bash
curl -X POST http://localhost:8099/webhook/feishu \
  -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"[测试] demo-app Pod 重启超过 3 次"}}'
```

平台顶部告警 badge 应立即变为黄色。

---

## 四、常见问题

### Q1: 代理在线但数据不更新
原因：port-forward 未启动。在第二个 WSL 终端运行：
```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090 &
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/loki-gateway 3100:80 &
```

### Q2: 终端页无法连接
原因：未安装 `websockets` 库。
```bash
pip install websockets
# 重启 proxy_server.py
```

### Q3: ArgoCD 应用列表为空
确认 ArgoCD 已部署：
```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd get applications
```

### Q4: 关闭服务后重启
关闭原窗口，重新双击 `start-proxy.bat` 或重新运行 `python3 proxy_server.py`。
集群本身不受影响，关闭的只是代理服务。

---

## 五、端口速查

| 地址 | 说明 | 凭据 |
|---|---|---|
| http://localhost:8099 | 运维平台首页 | — |
| http://localhost:8099/health | 健康检查 | — |
| ws://localhost:8098 | Web SSH | — |
| http://localhost:30300 | Grafana | admin / admin123 |
| https://localhost:30080 | ArgoCD | admin / wG0YYYIbLXX31dVf |
| http://localhost:9090 | Prometheus | —（需 port-forward） |
| http://localhost:3100 | Loki | —（需 port-forward） |

---

## 相关文档

- [Kind 多集群环境使用手册](https://my.feishu.cn/docx/KyfgdKymPokFgzxT6Ljc3auGnpg)
- [Kind 多集群故障手册](https://my.feishu.cn/docx/CNwudFGMnocYvRxjLngcFGaYnFh)
- [截图版使用手册](https://my.feishu.cn/docx/OIEJddSO8oTjMBxyMpNclogZnMF)
