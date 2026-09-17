# checkout-api

OpsHub 平台端到端走通的**示范应用**。演示用途：覆盖 OTel 埋点、Prometheus 指标、健康检查、SLO 关联。

## 特性

- **OpenTelemetry 埋点**：OTLP gRPC → Tempo（trace）+ Mimir（metric）+ 本地 Prometheus exporter
- **SLO 指标**：`http_requests_total`、`http_request_duration_seconds`、`http_errors_total`
- **健康检查**：startup / liveness / readiness 三类探针
- **可配置故障注入**：通过 env 控制错误率和延迟（演示 SLO burn rate 告警）
- **严格 Pod 安全**：`runAsNonRoot`、`readOnlyRootFilesystem`、drop ALL capabilities
- **多环境 overlay**：Kustomize 区分 prod / staging

## 快速运行

```bash
# 本地运行
cd app/checkout-api
go mod tidy
go run ./cmd

# 容器构建
docker build -t checkout-api:v0.1.0 .
docker run -p 8080:8080 -p 9090:9090 checkout-api:v0.1.0

# 测试
curl http://localhost:8080/healthz
curl http://localhost:8080/checkout/12345
curl http://localhost:9090/metrics
```

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SERVICE_NAME` | `checkout-api` | 服务名（OTel resource） |
| `SERVICE_VERSION` | `v0.1.0` | 版本 |
| `ENVIRONMENT` | `dev` | 环境标识 |
| `PORT` | `8080` | HTTP 端口 |
| `METRICS_PORT` | `9090` | Prometheus 指标端口 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `otel-collector.observability:4317` | OTel Collector 地址 |
| `OTEL_TRACES_SAMPLER_ARG` | `1.0` | 采样率（0.0-1.0） |
| `FAILURE_RATE` | `0.0` | 模拟错误率 |
| `LATENCY_MS` | `0` | 模拟延迟 |
| `DOWNSTREAM_URL` | `""` | 下游 URL（可选） |

## API 端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | Liveness 探针 |
| GET | `/readyz` | Readiness 探针 |
| GET | `/` | 服务信息 |
| GET | `/checkout/:orderId` | 查询订单 |
| POST | `/checkout` | 创建订单 |

## 关键 Prometheus 指标

| 指标 | 类型 | Labels | 用途 |
|---|---|---|---|
| `http_requests_total` | Counter | method, endpoint, status | 流量 + SLO 错误率分母 |
| `http_request_duration_seconds` | Histogram | endpoint | SLO 延迟 P95/P99 |
| `http_errors_total` | Counter | error.type | 错误率分母 |
| `http_requests_in_flight` | UpDownCounter | - | HPA 指标 |
| `runtime_*` | (Go runtime) | - | 进程健康 |

## SLO 范例（用于 Prometheus 告警）

```promql
# 可用性 SLO: 99.5% 成功
sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[5m]))
/
sum(rate(http_requests_total{job="checkout-api"}[5m]))
>= 0.995

# 延迟 SLO: 99% < 800ms
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le)
) < 0.8
```

## 演示用故障注入

```bash
# 注入 50% 错误率（演示告警触发）
kubectl set env deployment/checkout-api FAILURE_RATE=0.5 -n app-checkout-staging

# 注入 2s 延迟（演示 latency 告警）
kubectl set env deployment/checkout-api LATENCY_MS=2000 -n app-checkout-staging

# 观察：
# 1. Grafana 看 burn rate 上升
# 2. Alertmanager 触发 PagerDuty 告警
# 3. Prometheus rule 触发 → 通知 Slack
```

## 架构

```
[client]
   ↓ HTTP
[checkout-api pod]
   ├─ OTel SDK
   │   ├─ OTLP gRPC → otel-collector (in mgmt cluster) → Tempo
   │   └─ Prometheus exporter (port 9090) → Prometheus
   ├─ Health endpoints (/healthz, /readyz)
   └─ 业务 endpoints (/checkout, /checkout/:id)
```

## 部署

由 ArgoCD 通过 GitOps 部署：
- 源：`deploy/overlays/prod/` 或 `deploy/overlays/staging/`
- 同步策略：automated + selfHeal
- 失败自动回滚（依靠 Argo Rollouts 或 HPA）
