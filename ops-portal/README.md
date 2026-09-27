# Kind Ops Portal — 多集群运维平台

把 Kind 多集群环境（ArgoCD + Prometheus + Loki + Alertmanager + Sealed Secrets）的运维能力
收敛到一个页面。Node.js 后端 + 零框架前端。

```
浏览器  ──HTTP/WS──▶  Node.js 服务  ──kubectl/curl──▶  WSL Ubuntu  ──▶  Kind 集群
```

---

## 快速开始

```bash
# Windows
cd C:\Users\kim\kind-env\ops-portal
npm install          # 首次运行，安装 ws
npm start            # 或双击 start.bat
```

浏览器打开 **http://localhost:8099/**

告警和日志功能需要先做端口转发（另开一个 WSL 窗口）：

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-prometheus 9090:9090 &

wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/loki-gateway 3100:80 &
```

---

## 目录结构

```
ops-portal/
├── package.json          依赖（仅 ws）
├── start.bat             Windows 一键启动
├── server/
│   ├── index.js          入口：HTTP + 静态文件 + WebSocket + 优雅退出
│   ├── config.js         端口 / 集群 context / 端点集中配置
│   ├── k8s.js            kubectl、Helm、Prometheus、Loki 封装
│   ├── routes.js         API 路由表（手写 router，零依赖）
│   ├── alerts.js         告警聚合状态（Prometheus + Webhook + 操作事件）
│   └── terminal.js       WebSocket 交互终端 + 一次性命令执行
└── public/
    ├── index.html        8 个页面结构
    ├── styles.css        设计系统（CSS 变量 + 组件类）
    └── app.js            前端逻辑（ES Module，零框架）
```

---

## 页面

| 页面 | 功能 |
|---|---|
| 📊 概览 | 3 集群节点/Pod/告警/应用聚合指标，点击卡片跳转 |
| 🖥️ 集群 | 节点规格、命名空间 Pod 分布、Helm releases |
| 📦 Pods | 实时 Pod 列表，日志/describe/终端三个快捷入口，HPA + Services |
| 🔄 GitOps | ArgoCD 应用状态，一键同步/重启/历史/diff |
| 📋 日志 | LogQL 查询，时间窗口 + 行数可选 |
| 🚨 告警 | Prometheus firing / 飞书消息 / 操作事件 / 接入配置 四个标签页 |
| 💻 终端 | WebSocket 交互式 kubectl，另有一次性命令执行 |
| 🔗 工具 | 所有组件的直达链接与凭据 |

---

## API

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查（含 uptime、告警数） |
| GET | `/api/config` | 集群列表 + 常用命名空间 |
| GET | `/api/clusters` | 3 集群聚合 + 总计 |
| GET | `/api/cluster/:context` | 单集群详情 |
| GET | `/api/namespaces?context=` | 命名空间列表 + Pod 分布 |
| GET | `/api/pods?context=&namespace=` | Pod 列表 |
| GET | `/api/logs?pod=&namespace=&tail=` | kubectl logs |
| GET | `/api/pods/describe?pod=&namespace=` | kubectl describe |
| GET | `/api/hpa?context=&namespace=` | HPA 列表 |
| GET | `/api/services?context=&namespace=` | Service 列表 |
| GET | `/api/helm` | Helm releases |
| GET | `/api/argocd/apps?context=` | ArgoCD Application |
| POST | `/api/argocd/sync` | 触发同步 |
| POST | `/api/rollout-restart` | 滚动重启 |
| POST | `/api/scale` | 扩缩容 |
| GET | `/api/alerts` | 告警聚合快照 |
| GET | `/api/alerts/refresh` | 立即拉 Prometheus |
| POST | `/webhook/feishu` | 飞书告警接收 |
| GET | `/api/loki/query?q=&limit=&seconds=` | LogQL 查询 |
| GET | `/api/loki/labels` | Loki 标签 |
| GET | `/api/prom/query?expr=` | PromQL 即席查询 |
| GET | `/api/terminal/sessions` | 活跃终端列表 |
| POST | `/api/terminal/exec` | 一次性 kubectl 命令 |
| WS | `/ws/term` | 交互式终端 |

---

## WebSocket 终端协议

```json
// 客户端 → 服务端
{"type":"create","context":"kind-ops-mgmt","namespace":"demo-app","pod":"demo-app-xxx"}
{"type":"input","data":"kubectl get nodes\n"}
{"type":"run","context":"kind-ops-mgmt","namespace":"default","args":["get","pods","-A"]}
{"type":"close"}
{"type":"ping"}

// 服务端 → 客户端
{"type":"hello","data":"..."}
{"type":"ready","sessionId":"t1","data":"connected"}
{"type":"data","data":"输出内容"}
{"type":"result","ok":true,"data":"..."}
{"type":"error","data":"..."}
{"type":"exit","data":"..."}
```

**实现说明**：用 `child_process.spawn` 跑 `wsl ... kubectl exec -i`，没有分配真实 PTY。
好处是纯 JS、零原生依赖；代价是没有行编辑和彩色提示符。
需要完整 PTY 的话，把 `terminal.js` 里的 `spawn` 换成 `node-pty` 即可，接口不变。

---

## 飞书告警接入

平台暴露 `POST /webhook/feishu`，把 Alertmanager 指过来：

```yaml
# alertmanager-config.yaml
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

告警页的"接入配置"标签页有"发送测试消息"按钮，可以直接验证链路。

支持三种消息格式：`{msg_type:"text", content:{text}}`、飞书卡片、事件订阅 `im.message.receive_v1`。

---

## 配置

改环境变量或直接改 `server/config.js`：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `OPS_PORT` | 8099 | HTTP 端口 |
| `OPS_WS_PORT` | 8098 | WebSocket 端口 |
| `WSL_DISTRO` | Ubuntu | WSL 发行版 |
| `PROM_URL` | http://localhost:9090 | Prometheus |
| `LOKI_URL` | http://localhost:3100 | Loki |
| `CMD_TIMEOUT` | 30000 | 单命令超时（ms） |
| `WEBHOOK_SECRET` | — | 设置后 Webhook 需带 `X-Webhook-Secret` 头 |

---

## 快捷键

- `Ctrl/Cmd + R` — 刷新当前页数据
- `Esc` — 关闭弹窗
- `Enter` — 终端执行 / 日志查询

---

## 常见问题

**kubectl 报 command not found**
WSL 环境里没装 kubectl，或者 PATH 没生效。`server/config.js` 的 `wslDistro` 要跟实际发行版名一致。

**数据全是 0**
Kind 集群没起来。`wsl -d Ubuntu kind get clusters` 确认。

**告警/日志页面报错**
端口转发没做。见开头说明。

**终端没有彩色和 Tab 补全**
当前实现没分配 PTY，属预期行为。需要的话换 `node-pty`。
