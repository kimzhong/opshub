# OpsHub 项目索引

> 完整目录结构 + 文件清单 + 用途说明
> 顶层入口，从这里可以快速跳到任意子模块

---

## 顶层目录

```
opshub-platform-design/
├── 00-INDEX.md                  # 本文件
├── README.md                    # 项目总览（从这里开始）
├── 01-research/                 # 阶段 1：调研
├── 02-design/                   # 阶段 2：架构设计
├── 03-implementation/           # 阶段 3：实施代码
├── 04-封版报告.md                # 阶段 4：封版总结
└── .archive/                    # 一次性临时产物归档
```

---

## 阶段 1：调研（`01-research/`）

| 文件 | 用途 |
|---|---|
| `01-调研报告.md` | 11 个技术域选型 + 风险清单 |

11 个技术域：
1. 多集群管理
2. 容器镜像仓库
3. GitOps / CD
4. 可观测（Metrics/Logs/Traces）
5. 告警（SLO / Burn Rate）
6. IAM（OIDC / SSO）
7. 镜像签名 + 准入
8. 灾备（Velero / 跨区复制）
9. 混沌工程
10. IaC（Terraform / Crossplane）
11. 网络（Submariner / Service Mesh）

---

## 阶段 2：架构设计（`02-design/`）

| 文件 | 大小 | 用途 |
|---|---|---|
| `02-架构设计.md` | 25KB | 主架构 + 4 个 Mermaid 图（已转飞书画板 9 张）|
| `02-ADR.md` | 16KB | 11 个关键决策（含被否决方案）|
| `02-安全模型.md` | 14KB | 零信任 + IAM + RBAC + 加密 + 审计 |
| `02-容灾方案.md` | 16KB | 分层 RPO/RTO + 备份 + 复制 + 切换 + 演练 |

---

## 阶段 3：实施（`03-implementation/`）

### 3.1 kind 多集群（`kind/`）

| 文件 | 用途 |
|---|---|
| `clusters/ops-mgmt.yaml` | 1 control-plane + 2 worker，平台管理集群 |
| `clusters/biz-prod-regiona.yaml` | 业务集群 region A |
| `clusters/biz-prod-regionb.yaml` | 业务集群 region B |
| `create-clusters.ps1` | 一键创建（PS5.1 兼容）|
| `delete-clusters.ps1` | 一键销毁 |
| `README.md` | 多集群说明 |

### 3.2 ArgoCD（`argocd/`）

| 文件 | 用途 |
|---|---|
| `install-argocd.ps1` | 部署 ArgoCD + port-forward |
| `projects/opshub.yaml` | AppProject（多集群隔离）|
| `apps/root-app.yaml` | App of Apps 入口 |
| `apps/platform-applicationset.yaml` | 平台组件 ApplicationSet |
| `apps/biz-applicationset.yaml` | 业务应用 ApplicationSet |
| `clusters-secrets/README.md` | 多集群 secret 接入说明 |

### 3.3 可观测（`observability/`）

| 子目录 | 内容 |
|---|---|
| `prometheus/` | kube-prometheus-stack values + SLO 规则 |
| `loki/` | Loki values + 标签路由 |
| `tempo/` | Tempo values + 接收配置 |
| `mimir/` | Mimir values（长期指标）|
| `otel-collector/` | OpenTelemetry Collector DaemonSet |
| `alertmanager/` | 路由配置 + Slack/PagerDuty 集成 |

### 3.4 IAM（`iam/`）

| 文件 | 用途 |
|---|---|
| `keycloak/realm-export.json` | Keycloak 域导出（用户/组/客户端）|
| `dex/values.yaml` | Dex OIDC 代理配置 |
| `k8s-apiserver/oidc-config.yaml` | K8s API Server OIDC 接入 |

### 3.5 镜像供应链（`registry/`）

| 子目录 | 内容 |
|---|---|
| `harbor/` | 自管 Harbor values |
| `cosign/setup-cosign.ps1` | Cosign 密钥生成 + K8s secret 部署 |
| `kyverno/` | verifyImage + disallowPrivileged 策略 |

### 3.6 灾备（`backup/`）

| 文件 | 用途 |
|---|---|
| `velero/values.yaml` | Velero + S3 后端配置 |
| `velero/schedules.yaml` | 定时备份（每日 + 每周）|
| `velero/restore-script.sh` | 备份可恢复性自动验证 |

### 3.7 混沌（`chaos/`）

| 文件 | 用途 |
|---|---|
| `chaos-mesh/values.yaml` | Chaos Mesh Helm 配置 |
| `experiments/podchaos.yaml` | Pod 失败实验 |
| `experiments/networkchaos.yaml` | 网络分区实验 |

### 3.8 示范应用（`app/checkout-api/`）

| 路径 | 内容 |
|---|---|
| `cmd/main.go` | Go HTTP 服务 + OTel 埋点 |
| `internal/handler/` | checkout / payment / refund API |
| `internal/telemetry/` | OTel tracer / meter 配置 |
| `deploy/base/` | Deployment + Service + ConfigMap |
| `deploy/overlays/{staging,prod}/` | Kustomize 环境差异化（副本数/资源/故障注入 env）|

### 3.9 IaC（`iac/`）

```
iac/
├── README.md
├── terraform/
│   ├── main.tf                   # AWS + VPC + EKS + RDS + S3
│   ├── variables.tf              # 8 个变量
│   └── README.md
└── crossplane/
    ├── providers.yaml            # 7 个 Provider + AWS 凭据
    ├── compositions/
    │   ├── postgres.yaml         # XPostgresDatabase → RDS
    │   ├── redis.yaml            # XRedisCluster → ElastiCache
    │   ├── rabbitmq.yaml         # XRabbitMQCluster → Amazon MQ
    │   └── s3-bucket.yaml        # XBucket → S3 + KMS + 公开锁
    └── README.md
```

### 3.10 故障注入（`scripts/`）

| 脚本 | 用途 |
|---|---|
| `inject-pod-failure.ps1` | 杀一个 pod + 观察告警 |
| `inject-slo-burn.ps1` | 2min 高错误率 + SLO 告警 |
| `simulate-region-failure.ps1` | 删 region A 集群 + 跨区切换 |
| `dr-drill/monthly-dr-drill.ps1` | 月度全流程演练 + 报告 |
| `onboarding/onboard-new-cluster.ps1` | 新集群接入 helper |

### 3.11 飞书画板（`whiteboards/`）

| 文件 | 用途 |
|---|---|
| `tokens.json` | 9 个飞书画板 token + 标题索引 |

### 3.12 文档（`docs/`）

| 文件 | 用途 |
|---|---|
| `部署与运维手册.md` | 5 分钟启动 + 部署步骤 + 运维要点 |
| `测试报告.md` | 4 维度验证（语法/结构/逻辑/集成）|

---

## 阶段 4：封版（`04-封版报告.md`）

封版总结：所有交付物清单 + 验证状态 + 飞书沉淀位置 + 后续可优化项。

---

## 关键统计

- 阶段 1：1 份调研（11 域）
- 阶段 2：4 份架构（72KB，11 个 ADR）
- 阶段 3：80+ 实施文件 + 9 个 PS1 + 7 个 IaC + 1 个 Go 应用
- 飞书：8 份文档 + 9 张画板
- 验证：YAML 30/30 + Go 1/1 + PS1 9/9 + Mermaid 9/9

---

## 飞书入口

| 文档 | doc_id | 链接 |
|---|---|---|
| 项目总览 | GAbSdK4syoz8mrxX221cpRttn2e | https://my.feishu.cn/docx/GAbSdK4syoz8mrxX221cpRttn2e |
| 01-调研 | ZBkGdQkZQoWUj2xQWMQcGnyWnOd | https://my.feishu.cn/docx/ZBkGdQkZQoWUj2xQWMQcGnyWnOd |
| 02-架构 | TAsHdCyLGony1GxQxs5cjXgwnic | https://my.feishu.cn/docx/TAsHdCyLGony1GxQxs5cjXgwnic |
| 02-ADR | HPIkdEUtno95bVxJsxQcH4vBnkb | https://my.feishu.cn/docx/HPIkdEUtno95bVxJsxQcH4vBnkb |
| 02-安全 | A2fvdKm8momqUBxwSRKcBuuRnmd | https://my.feishu.cn/docx/A2fvdKm8momqUBxwSRKcBuuRnmd |
| 02-容灾 | Dx30dve6UoS56SxkilwciYNZnxb | https://my.feishu.cn/docx/Dx30dve6UoS56SxkilwciYNZnxb |
| 03-部署 | Hdgmdge3voOsH3xISkucDhVTnZg | https://my.feishu.cn/docx/Hdgmdge3voOsH3xISkucDhVTnZg |
| 测试报告 | WGdWdOf2PoCawJx9tsgcx1rbnTh | https://my.feishu.cn/docx/WGdWdOf2PoCawJx9tsgcx1rbnTh |
