# OpsHub 实施代码（03-implementation）

> 可运行的端到端代码骨架，覆盖：
> kind 多集群 → ArgoCD GitOps → 可观测 → IAM → 镜像供应链 → 混沌 → 灾备 → 故障注入 → IaC

## 目录总览

```
03-implementation/
├── kind/                       # kind 多集群（3 YAML + 2 PS1 + README）
├── argocd/                     # ArgoCD App of Apps + Project + ApplicationSet
├── observability/              # Prometheus + Grafana + Loki + Mimir + Tempo + OTel
├── iam/                        # Keycloak realm + Dex OIDC + API Server 配置
├── registry/                   # Harbor + Cosign + Kyverno 准入
├── backup/                     # Velero 备份 + schedules + 验证脚本
├── chaos/                      # Chaos Mesh + PodChaos/NetworkChaos 实验
├── app/checkout-api/           # Go 示范应用 + OTel 埋点 + 多环境 overlay
├── iac/                        # IaC 资产（Terraform 基础 + Crossplane 应用）
│   ├── terraform/              # AWS 账号/VPC/EKS/IAM
│   └── crossplane/             # Compositions + Providers（Postgres/Redis/RabbitMQ/S3）
├── scripts/                    # 故障注入 + DR Drill 剧本
│   ├── inject-pod-failure.ps1
│   ├── inject-slo-burn.ps1
│   ├── simulate-region-failure.ps1
│   ├── dr-drill/monthly-dr-drill.ps1
│   └── onboarding/onboard-new-cluster.ps1
├── whiteboards/                # 9 个飞书画板 token 表
│   └── tokens.json
└── docs/                       # 部署与运维手册 + 测试报告
```

## 5 分钟启动

```powershell
# 1. 创建多集群（5-10 min）
cd 03-implementation
.\kind\create-clusters.ps1

# 2. 部署 ArgoCD（ops-mgmt 集群）
.\argocd\install-argocd.ps1

# 3. 部署镜像签名
.\registry\cosign\setup-cosign.ps1

# 4. 部署监控栈
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring --create-namespace `
  --values observability\prometheus\kube-prometheus-stack-values.yaml
# 其他组件参考 docs/部署与运维手册.md

# 5. 部署示范应用
kubectl apply -f app\checkout-api\deploy\overlays\staging\ -n app-checkout-staging

# 6. 触发故障演练
.\scripts\inject-slo-burn.ps1
```

## 模块清单

| 模块 | 关键文件 | 验证方式 |
|---|---|---|
| **kind 多集群** | `kind/clusters/*.yaml` + `kind/create-clusters.ps1` | `kubectl get nodes --context ops-mgmt` |
| **ArgoCD** | `argocd/install-argocd.ps1` + `argocd/apps/*.yaml` | https://localhost:30443 |
| **可观测** | `observability/{prometheus,loki,tempo,mimir,otel-collector,alertmanager}/` | `kubectl get pods -n monitoring` |
| **IAM** | `iam/keycloak/realm.json` + `iam/dex/values.yaml` | `kubectl get keycloakrealm` |
| **镜像供应链** | `registry/{harbor,cosign,kyverno}/` | `cosign verify <image>` |
| **灾备** | `backup/velero/{values,schedules}*.yaml` | `velero backup get` |
| **混沌** | `chaos/chaos-mesh/values.yaml` + `chaos/experiments/*.yaml` | `kubectl get podchaos` |
| **示范应用** | `app/checkout-api/cmd/main.go` | `curl /checkout/test` |
| **IaC 基础** | `iac/terraform/main.tf` | `terraform plan` |
| **IaC 应用** | `iac/crossplane/compositions/*.yaml` | `kubectl get xpostgresdatabases` |
| **故障注入** | `scripts/inject-*.ps1` | 触发 + 验证告警 |
| **DR Drill** | `scripts/dr-drill/monthly-dr-drill.ps1` | 生成报告 `drill-reports/dr-*.md` |
| **飞书画板** | `whiteboards/tokens.json` | 9 张图已发飞书 02-架构 docx |

## 9 个 PS1 脚本（PS5.1 兼容）

| 脚本 | 用途 |
|---|---|
| `kind/create-clusters.ps1` | 创建 ops-mgmt + 2 业务集群 |
| `kind/delete-clusters.ps1` | 销毁所有 kind 集群 |
| `argocd/install-argocd.ps1` | 部署 ArgoCD + port-forward |
| `registry/cosign/setup-cosign.ps1` | 部署 Cosign + Kyverno |
| `scripts/inject-pod-failure.ps1` | 故障注入：Pod 失败 + 告警 |
| `scripts/inject-slo-burn.ps1` | 故障注入：SLO Burn Rate 告警 |
| `scripts/simulate-region-failure.ps1` | 故障注入：Region 故障切换 |
| `scripts/dr-drill/monthly-dr-drill.ps1` | 月度 DR 演练剧本 + 报告 |
| `scripts/onboarding/onboard-new-cluster.ps1` | 新集群接入 helper |

全部 9 个脚本已经过 PS5.1 AST 解析器严格验证通过（0 errors）。

## IaC 资产

| 文件 | 用途 |
|---|---|
| `iac/terraform/main.tf` | AWS 账号 + VPC + EKS + RDS + S3 backup |
| `iac/terraform/variables.tf` | 8 个平台变量 |
| `iac/crossplane/providers.yaml` | 7 个 Provider + ProviderConfig + AWS 凭据 |
| `iac/crossplane/compositions/postgres.yaml` | XPostgresDatabase（RDS PostgreSQL）|
| `iac/crossplane/compositions/redis.yaml` | XRedisCluster（ElastiCache）|
| `iac/crossplane/compositions/rabbitmq.yaml` | XRabbitMQCluster（Amazon MQ）|
| `iac/crossplane/compositions/s3-bucket.yaml` | XBucket（S3 + KMS + 公开锁 + 跨区复制）|

## 故障注入剧本

1. **Pod 失败** — HPA 自动扩容 + 告警
2. **SLO 告警** — 2min 高错误率触发 burn rate
3. **Region 故障** — 删集群 + 跨区流量切换
4. **DR Drill** — 月度全流程演练 + 报告

详细使用见 `docs/部署与运维手册.md`。
