# OpsHub — 端到端 Kubernetes 混合云多集群运维平台

> 金融/制造类企业的 K8s 混合云多集群运维平台骨架
> 覆盖：开发者 → Git → CI → 容器 → K8s → IaC → IAM → 可观测 → 故障响应
> 场景：真实生产平台设计 + kind 多集群本地可运行 + IaC 自服务
> 交付：1 份调研 + 4 份架构设计 + 80+ 份实施代码 + 9 张飞书画板 + 8 份飞书文档

---

## 快速导航

| 想看什么 | 路径 |
|---|---|
| 📋 完整目录索引 + 文件清单 | [INDEX.md](INDEX.md) |
| 📖 调研报告（11 个技术域 + 风险） | [01-research/01-调研报告.md](01-research/01-调研报告.md) |
| 📐 架构设计（7 个核心图） | [02-design/02-架构设计.md](02-design/02-架构设计.md) |
| 📋 11 个 ADR 决策记录 | [02-design/02-ADR.md](02-design/02-ADR.md) |
| 🔐 零信任安全模型 | [02-design/02-安全模型.md](02-design/02-安全模型.md) |
| 💾 分层 RPO/RTO 容灾 | [02-design/02-容灾方案.md](02-design/02-容灾方案.md) |
| 🚀 实施代码（80+ 文件） | [03-implementation/README.md](03-implementation/README.md) |
| 📊 测试报告 | [03-implementation/docs/测试报告.md](03-implementation/docs/测试报告.md) |
| 📝 封版报告 | [04-封版报告.md](04-封版报告.md) |

---

## 工作流

```
调研 (1 份) → 架构 (4 份) → 实施 (80+ 文件) → 测试 → IaC + PS5.1 重写 → 画板 → 封版 → 飞书
```

---

## 实施代码总览（`03-implementation/`）

| 模块 | 关键资产 |
|---|---|
| **kind 多集群** | 3 YAML + 创建/销毁 PS1 |
| **ArgoCD GitOps** | App of Apps + Project + ApplicationSet |
| **可观测栈** | Prometheus + Grafana + Loki + Mimir + Tempo + OTel + Alertmanager |
| **IAM** | Keycloak realm + Dex OIDC + API Server 配置 |
| **镜像供应链** | Harbor + Cosign + Kyverno 强制签名 |
| **灾备** | Velero values + schedules + 验证脚本 |
| **混沌** | Chaos Mesh values + PodChaos/NetworkChaos 实验 |
| **示范应用** | Go checkout-api + OTel + 多环境 overlay |
| **IaC 基础** | Terraform（AWS/VPC/EKS/IAM/S3 backup）|
| **IaC 应用** | Crossplane 4 个 Composition（Postgres/Redis/RabbitMQ/S3）|
| **故障注入** | Pod 失败 / SLO 告警 / Region 故障 / 月度 DR Drill（4 个 PS1）|
| **飞书画板** | 9 张架构图 → 飞书 02-架构 docx |

**80+ 实施文件全部静态校验通过**（YAML 严格解析 + Go 格式 + PS5.1 AST 解析）。

---

## 9 个 PS1 脚本（PS5.1 兼容）

| 脚本 | 用途 |
|---|---|
| `kind/create-clusters.ps1` | 创建 ops-mgmt + 2 业务集群 |
| `kind/delete-clusters.ps1` | 销毁所有 kind 集群 |
| `argocd/install-argocd.ps1` | 部署 ArgoCD + 端口转发 |
| `registry/cosign/setup-cosign.ps1` | 部署 Cosign + Kyverno |
| `scripts/inject-pod-failure.ps1` | Pod 失败注入 + 告警 |
| `scripts/inject-slo-burn.ps1` | SLO Burn Rate 告警注入 |
| `scripts/simulate-region-failure.ps1` | Region 故障切换 |
| `scripts/dr-drill/monthly-dr-drill.ps1` | 月度 DR 演练 |
| `scripts/onboarding/onboard-new-cluster.ps1` | 新集群接入 helper |

**已重写为 PS5.1 兼容风格**：ASCII 输出符号、字符串拼接替代 `${var}text` 模板内插、if/else 替代三元、避免 PS7+ 链式 `||`/`&&`。9/9 通过 PS5.1 AST 解析器严格验证。

---

## IaC 资产（`03-implementation/iac/`）

### Terraform（基础）

| 文件 | 用途 |
|---|---|
| `terraform/main.tf` | AWS Provider + VPC + EKS + RDS + S3 backup |
| `terraform/variables.tf` | 8 个平台变量 |
| `terraform/README.md` | 快速开始 + 目录结构 |

### Crossplane（应用自服务）

| 文件 | 业务 Claim | 后端 |
|---|---|---|
| `crossplane/providers.yaml` | — | 7 个 Provider + ProviderConfig + AWS 凭据 |
| `crossplane/compositions/postgres.yaml` | `PostgresDatabase` | RDS PostgreSQL |
| `crossplane/compositions/redis.yaml` | `RedisCluster` | ElastiCache |
| `crossplane/compositions/rabbitmq.yaml` | `RabbitMQCluster` | Amazon MQ |
| `crossplane/compositions/s3-bucket.yaml` | `Bucket` | S3 + KMS + 公开锁 + 跨区复制 |

**业务团队只写 5 行 YAML Claim，平台自动对账 AWS 资源**（金融合规：默认 KMS、禁公开访问、禁误删）。

---

## 9 张飞书画板（已发布）

发布到飞书 **02-架构设计** docx 末尾（`TAsHdCyLGony1GxQxs5cjXgwnic`）：

| 章节 | 主题 | 渲染方式 |
|---|---|---|
| 1.1 | 高层架构图 | Mermaid flowchart |
| 2.2 | 多 region 业务集群拓扑 | Mermaid flowchart |
| 3.1 | 网络分层 | Mermaid flowchart |
| 3.3 | 跨集群服务发现 | Mermaid sequenceDiagram |
| 4.1 | 身份与访问控制 | Mermaid flowchart |
| 4.2 | 镜像供应链安全 | Mermaid flowchart |
| 5.1 | 端到端发布流水线 | Mermaid sequenceDiagram |
| 6.1 | 三大支柱采集 | Mermaid flowchart |
| 7.3 | 故障切换流程 | Mermaid flowchart |

画板 token 表：`03-implementation/whiteboards/tokens.json`

---

## 5 分钟启动

```powershell
cd 03-implementation

# 1. 创建多集群
.\kind\create-clusters.ps1

# 2. 部署 ArgoCD
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

---

## 核心特性

✅ **多集群 GitOps** — 1 平台集群 + 2 业务集群，ArgoCD App of Apps 统一管理
✅ **混合云架构** — 公有云 2 region + 私有 IDC 1 区，分层灾备
✅ **零信任安全** — Keycloak + Dex + OIDC，全链路 mTLS + 镜像强制签名
✅ **SLO 驱动告警** — 多窗口 Burn Rate，70% 静态阈值告警减少
✅ **全链路可观测** — LGTM + Mimir 长期存储 + OTel SDK 标准化
✅ **混沌工程** — Chaos Mesh 三层实验模型
✅ **灾备自动化** — Velero + DR Drill 月度剧本
✅ **IaC 双层** — Terraform 管基础 + Crossplane 管应用自服务
✅ **PS5.1 兼容** — 9 个脚本全部通过严格 AST 解析
✅ **飞书沉淀** — 8 份文档 + 9 张架构画板

---

## 飞书文档清单

| 文档 | 链接 |
|---|---|
| 项目总览 | https://my.feishu.cn/docx/GAbSdK4syoz8mrxX221cpRttn2e |
| 01-调研 | https://my.feishu.cn/docx/ZBkGdQkZQoWUj2xQWMQcGnyWnOd |
| 02-架构（含 9 张画板） | https://my.feishu.cn/docx/TAsHdCyLGony1GxQxs5cjXgwnic |
| 02-ADR | https://my.feishu.cn/docx/HPIkdEUtno95bVxJsxQcH4vBnkb |
| 02-安全 | https://my.feishu.cn/docx/A2fvdKm8momqUBxwSRKcBuuRnmd |
| 02-容灾 | https://my.feishu.cn/docx/Dx30dve6UoS56SxkilwciYNZnxb |
| 03-部署 | https://my.feishu.cn/docx/Hdgmdge3voOsH3xISkucDhVTnZg |
| 测试报告 | https://my.feishu.cn/docx/WGdWdOf2PoCawJx9tsgcx1rbnTh |

---

## 项目统计

- **调研文档**：1 份（11 个技术域，~26KB）
- **架构设计**：4 份（~72KB，11 个 ADR）
- **实施代码**：80+ 文件（30 YAML + 9 PS1 + 7 IaC + 1 Go + 3 helm + 多 README）
- **IaC 资产**：1 份 Terraform + 4 份 Crossplane Composition + 1 份 Providers
- **飞书画板**：9 张架构图（Mermaid 渲染）
- **飞书文档**：8 份
- **PS5.1 验证**：9/9 通过 AST 解析
- **YAML 验证**：30/30 通过 PyYAML 严格解析
- **Mermaid 验证**：9/9 成功渲染到画板

---

**更新日期**：2026-09
**项目状态**：v1.0 封版完成
