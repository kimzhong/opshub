# 架构决策记录（ADR / Architecture Decision Records）

> 目的：记录 OpsHub 平台中**关键决策**的上下文、选项、被否决方案、最终决定。
> 编号规则：ADR-NNN，按时间倒序（新决策在上）。

---

## ADR-001：使用 ArgoCD 作为 GitOps 控制器（而非 Flux）

**日期**：2026-09-06
**状态**：✅ Accepted
**决策者**：SRE 平台团队

### 背景

需要选择 K8s 上的 GitOps 工具，统一管理多集群的应用交付。

### 选项

| 选项 | 优点 | 缺点 |
|---|---|---|
| **ArgoCD** | UI 强大、ApplicationSet 跨集群生态成熟、Notifications 内置 | 资源占用较重（API+UI+Redis） |
| Flux v2 | 轻量、纯 CRD、image-automation 内置 | 无内置 UI（运维/审计弱）、多租户 RBAC 较弱 |
| 自研 | 完全可控 | 维护成本极高、重复造轮子 |

### 决定

选 **ArgoCD**。

### 理由

1. **多集群是核心场景**：ArgoCD 的 ApplicationSet + Cluster generator 是多集群 GitOps 事实标准
2. **审计/演示需求**：金融/制造场景常需给审计/管理层展示应用状态，ArgoCD Web UI 是天然看板
3. **生态完整性**：Argo Rollouts（渐进式发布）、Argo Events（事件驱动）、Argo Workflows（流水线）同生态
4. **企业采用率**：BlackRock、Stripe、Ant Group 等金融场景已验证

### 否决 Flux 的关键点

- 缺乏 UI 对 SRE 团队日常运维不友好
- 跨集群 ApplicationSet 比 Flux 的 Kustomization 模式直观
- image-automation 虽好，但可用外部 CI 工具补充

### 后果

- 需要 HA 部署 ArgoCD（多副本 + Redis Sentinel/Cluster）
- 团队需要学习 ArgoCD RBAC 模型（Project + Casbin 策略）
- 监控 ArgoCD 自身（Application CRD 数量、sync 状态、repo-server 性能）

### 后续

- 如果未来 UI 出现性能瓶颈，可考虑 Weave GitOps Enterprise 替代
- 保留 Flux 作为备选（迁移路径已验证：Application → Kustomization 转换有开源工具）

---

## ADR-002：CI 用 GitHub Actions + Tekton（而非单一工具）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

CI 是平台的关键组件，需要支持：构建、测试、扫描、签名、镜像推送、多环境 promotion。

### 决策矩阵

| 工具 | 优点 | 缺点 | 适合 |
|---|---|---|---|
| Jenkins | 生态成熟、灵活 | 维护成本高、插件治理差 | 传统企业、有 Jenkins 资产的 |
| GitHub Actions | 易用、市场 20k+ actions | SaaS 强绑定（安全要求不通过）、企业功能付费 | 简单 CI |
| GitLab CI | 一体化 | 绑定代码托管 | 已用 GitLab |
| Tekton | K8s 原生、CRD、可组合 | 学习曲线陡 | 平台型团队 |
| Argo Workflows | DAG 编排灵活 | 不是 CI 工具 | 多步流水线编排 |
| Buildkite | 混合（自建 runner）| 商业、定价 | 大型高合规需求 |

### 决定

**GitHub Actions（构建/单测/扫描）+ Tekton（复杂流水线编排）**。

- 如果用户接受 GitHub Enterprise Server（自管），则用 GHA
- 如果要求完全开源本地代码托管，则改用 Gitea Actions + Tekton 替代

### 理由

1. **构建与编排解耦**：构建/单测是开发高频动作，放 GHA 拉新最快；多步 promotion 是平台负责，放 Tekton 集中管控
2. **复用而非自建**：Tekton 是 K8s 生态标准，Openshift Pipelines 用它，IBM/Google 内部都基于它
3. **未来可扩展**：Tekton Hub 提供 100+ 可复用 Task

### 否决单工具的考虑

- 纯 Tekton：开发体验不够丝滑（无 marketplace 概念）
- 纯 GHA：无法很好支持"多环境 promotion 编排"
- 纯 Argo Workflows：CI 概念不如 Tekton 完整

### 后果

- 需要维护两套系统的运维
- 开发需要学习两套配置（.github/workflows/*.yml + Tekton PipelineRun YAML）
- Tekton 资源占用需要监控（TaskRun 数量）

---

## ADR-003：IaC 用 Terraform + Crossplane 双层（而非单一工具）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

需要管理：
1. 云上基础资源（VPC、RDS、ACK、IAM 角色）—— **不可变**，变更频率低
2. 业务应用需要的中间件（RDS 实例、Redis、消息队列）—— **频繁创建/销毁**

### 决策

**Terraform（基础层）+ Crossplane（应用自服务层）**。

### 理由

1. **Terraform 管云上基础**：生态最广（3500+ provider）、plan/apply 模式有 audit 价值、状态文件管理成熟
2. **Crossplane 给开发者自助**：业务团队通过 `PostgresClaim` / `RedisClaim` 自助申请，平台团队用 Composition 控制
3. **零状态文件**：Crossplane 直接用 K8s etcd，没有 Terraform state 锁/损坏问题
4. **天然 GitOps**：Crossplane 资源可被 ArgoCD 直接管理

### 否决方案

- **纯 Crossplane 管云上基础网络**：跨集群/跨账号管理复杂，CRD 抽象可能丢失细节
- **纯 Terraform 管应用中间件**：状态文件易冲突，频繁变更性能差
- **Pulumi**：生态小（依赖 Terraform provider bridge），学习曲线高，业务场景不见得划算

### 后果

- 平台团队要维护两套工具栈
- 需要清晰的边界：哪些资源用 Terraform、哪些用 Crossplane
- Crossplane Composition 需要时间沉淀（不可能一开始就有完整 Compositions）

### 边界定义

| 资源类型 | 用 Terraform | 用 Crossplane |
|---|---|---|
| VPC / 子网 / 路由表 | ✅ | ❌ |
| 安全组 / NACL | ✅ | ❌ |
| K8s 集群本身 | ✅ | ❌ |
| IAM 角色 / 策略 | ✅ | ❌ |
| 持久存储（云盘） | ✅ | ❌ |
| 数据库实例 | ❌（少量） | ✅（业务自服务） |
| 缓存实例 | ❌ | ✅ |
| 消息队列 | ❌ | ✅ |
| 对象存储桶 | ✅ | ❌ |
| 业务应用资源 | ❌ | ❌（直接 K8s YAML） |

---

## ADR-004：身份用 Keycloak + Dex 联合（而非 Keycloak 直连 K8s）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

多 K8s 集群需要统一身份认证；公司已有 AD/LDAP/GitHub Enterprise 作为身份源。

### 决策

**Keycloak 作中心 IdP，Dex 作 K8s API OIDC 代理**。

### 理由

1. **Dex 解决多集群 OIDC 痛点**：所有 K8s API Server 都挂同一个 Dex issuer 即可，无需每个集群都配 Keycloak
2. **Dex 联邦多个 IdP**：可以把 AD、GitHub、LDAP 等都转成 K8s 认识的 OIDC
3. **Dex 缓存 + 短 token**：减少对 Keycloak 的请求，提升 K8s API 性能
4. **Keycloak 解耦 OIDC 之外的协议**：SAML、社交登录、用户管理交给 Keycloak

### 否决方案

- **Keycloak 直连 K8s**：每个集群 API Server 都配 Keycloak，配置复杂；Keycloak 集群本身故障 = 全部集群认证失效
- **Ory Hydra**：相对小众，文档/社区不如 Keycloak
- **云厂商托管 IdP（AWS IAM Identity Center）**：违反"安全为硬性底线"原则

### 后果

- 多一层组件（Dex），增加维护成本
- Keycloak 故障的影响面 = 全部业务集群（必须 HA 部署）
- 离线 break-glass 凭证必备

---

## ADR-005：监控用 LGTM + Mimir（而非 Datadog/New Relic SaaS）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

业务要求"安全为硬性底线"——身份与可观测必须本地，不能上 SaaS。

### 决策

**Prometheus + Grafana + Loki + Tempo + Mimir + OpenTelemetry**（即 LGTM+），全部自管。

### 理由

1. **合规硬性要求**：金融/医疗/政务场景不接受可观测数据上云
2. **成本可控**：20 服务规模 Datadog $30k/月 vs 自建 $2k/月 + 工程师时间
3. **OTel 标准化**：用 OpenTelemetry SDK 注入，切换后端不改代码
4. **CNCF 生态完整**：所有组件都是 CNCF Graduated/Incubating
5. **数据驻留**：所有 metric/log/trace 都在本地 IDC

### 否决方案

- **Datadog / New Relic / Dynatrace**：违反合规、数据上云、成本高
- **Elastic Stack**：全文本索引存储成本比 Loki 高 3-10x
- **Splunk**：贵（$20k+/月）

### 后果

- 工程师需要维护可观测栈（升级、扩容、调优）
- 初期功能不如 SaaS 丰富（无 AIOps 智能告警——可后期集成开源 ML 工具）
- 长期存储成本需要管理（Mimir 对象存储分片策略）

### 自研 vs 商业的边界

- 自研 LGTM+：满足 80% 场景
- 商业 AIOps 工具可后补：选 SigNoz / Coroot 等开源 + 自建 ML 告警

---

## ADR-006：多集群拓扑选 Hub-Spoke（而非 Federation）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

需要管理多 region、多环境 K8s 集群。

### 决策

**Hub-Spoke 拓扑 + Cluster API 供给 + ArgoCD 集中管控**，**不引入 meta-control-plane**。

### 集群角色

- **Hub（ops-mgmt）**：私有 IDC，单 region，HA 部署
- **Spoke（biz-*）**：公有云多 region，Cluster API 声明式管理

### 理由

1. **KubeFed 已死**：v1/v2 在 2023-04 归档，SIG Multicluster 弃坑
2. **避免 meta-control-plane 单点**：KubeFed/Karmada 的"集中 API server"是 etcd + SPOF
3. **每个 spoke 独立生命周期**：cluster 可任意销毁重建（cattle 模型）
4. **GitOps 协调而非 API 协调**：Git 是事实源，spoke 集群从 Git pull

### 否决方案

- **KubeFed/Karmada**：已废弃/特殊场景
- **单集群跨云**：etcd 跨公网延迟是灾难
- **裸 ArgoCD + 多集群 secret**：管理混乱，无集中管控

### 后果

- 跨集群调用需要 Submariner 隧道（增加 ~10-50ms 延迟）
- 不适合"频繁跨集群调用"的工作负载（应避免这种设计）
- spoke 集群升级/扩容通过修改 Cluster API 资源，GitOps 自动应用

---

## ADR-007：灾备用分层 RPO/RTO（而非统一方案）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

业务有不同等级，灾备需求差异巨大。统一方案要么过度投入、要么不足。

### 决策

**按业务等级分层灾备策略**：

| 等级 | 数量（占比）| RPO | RTO | 实现 |
|---|---|---|---|---|
| Tier 0 | 1-3 服务 | < 1 min | < 5 min | 双 region active-active + DB sync |
| Tier 1 | 5-10 服务 | < 5 min | < 30 min | 双 region active-passive |
| Tier 2 | 10+ 服务 | < 1h | < 4h | 跨 region backup-restore |
| Tier 3 | 任意 | < 24h | < 24h | 同 region 备份 |

### 理由

1. **成本与业务价值匹配**：核心交易值得双活成本；内部工具不值得
2. **资源优化**：80% 业务用 Tier 2/3 即可，只有 5-10% 业务需要 Tier 0
3. **避免过度工程**：所有业务都上 active-active 是浪费

### 否决方案

- **全部 active-active**：成本翻倍、对小业务不划算
- **全部 backup-restore**：核心业务不可接受
- **两地三中心**：金融核心才需要，本项目双 region 已足够

### 后果

- 需要业务等级评定（业务上线前 review）
- 灾备演练按等级频率（Tier 0 月度、Tier 1 季度、Tier 2 半年）
- 数据库复制拓扑复杂（同步 + 异步混合）

---

## ADR-008：镜像签名用 Cosign + Kyverno（而非 Notary v2）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

供应链安全是金融场景的硬性要求，需要确保只有经过审查的镜像能在生产集群运行。

### 决策

**Cosign（签名）+ Kyverno（强制准入）+ Sigstore TLog（审计）**。

### 理由

1. **Cosign 是 CNCF 标准**（Sigstore 项目，2023 毕业）
2. **Kyverno 用 YAML 写策略**（vs OPA Rego），运维友好
3. **Sigstore TLog 提供不可篡改的签名记录**（类似区块链）
4. **OCI 标准原生**：签名作为 OCI artifact 存在，不依赖外部存储

### 否决方案

- **Notary v2**：是 Docker 官方方案，但生态不如 Cosign
- **OPA Gatekeeper**：需要学 Rego，对 SRE 团队不友好
- **无签名 + 漏洞扫描**：扫描只防已知漏洞，防不了"恶意代码被构建进镜像"

### 后果

- 必须在 CI 阶段集成 Cosign 签名（pipeline 改造）
- K8s 准入控制增加 50-100ms 延迟（可接受）
- Harbor 镜像元数据增加（signature 占用空间）

---

## ADR-009：告警用 SLO Burn Rate（而非静态阈值）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

传统静态阈值告警（如 "CPU > 80%"）是 on-call 团队最大的痛点。

### 决策

**所有 paging 告警基于 SLO Burn Rate**（Google SRE Workbook 标准），结合多窗口（5min / 30min / 1h / 6h）分级。

### 理由

1. **PagerDuty 内部数据**：70% 静态阈值告警无需响应
2. **Honeycomb 案例**：切换到 SLO 告警后 page 量从 15-20/周 降到 3-4/周
3. **alert 与用户影响挂钩**：SLO 烧速 = 用户正在受影响的速度
4. **避免告警疲劳**：保留 1+2 个高 severity burn rate 即可，安静期

### 否决方案

- **静态阈值**：70% 误报、漏报慢
- **AI 异常检测**：成本高、调参难、对小规模过度工程
- **Prometheus 默认告警规则**：质量参差不齐，不适合生产

### 后果

- 业务上线前**必须**定义 SLO YAML
- 平台团队提供 SLO 模板（降低业务团队负担）
- 告警规则需要定期审计（每季度）

---

## ADR-010：混沌工程用 Chaos Mesh + LitmusChaos（而非单一工具）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

需要建立"持续验证"文化，确保系统韧性。

### 决策

**Chaos Mesh（细粒度故障）+ LitmusChaos（多步实验）**。

### 理由

1. **Chaos Mesh 故障类型最全**：PodChaos / NetworkChaos / IOChaos / TimeChaos / DNSChaos / StressChaos
2. **LitmusChaos ChaosHub 社区实验丰富**：AWS/GCP/Azure 故障模板现成
3. **LitmusChaos Workflow 支持多步实验**：可编排"先杀 Pod → 观察 5min → 杀节点"等链式
4. **两者都是 CNCF 项目**：生态活跃、文档完整

### 否决方案

- **Gremlin**：商业 SaaS，违反合规
- **AWS Fault Injection Service / Azure Chaos Studio**：绑定云厂商，混合云场景不便
- **Chaos Monkey**：仅 VM 故障，已不维护

### 后果

- 维护两套混沌平台
- 团队需要学两套 CRD 语法
- 必须在 SLO/SLI 体系建立后再推混沌（先有"已知稳态"才能验证故障）

### 三层实验模型

| 层 | 频率 | 工具 | 实验 |
|---|---|---|---|
| Tier 1：Pod | 每日/自动 | Chaos Mesh | kill pod, CPU stress |
| Tier 2：Node | 每周/自动 | Chaos Mesh | drain node, AZ kill |
| Tier 3：Region | 季度/game day | LitmusChaos | partition, region switch |

---

## ADR-011：本地开发用 kind 多集群（而非 minikube / k3d）

**日期**：2026-09-06
**状态**：✅ Accepted

### 背景

需要本地开发/演示多集群编排，模拟生产的多集群环境。

### 决策

**kind 多集群**（1 mgmt + 2 workload）。

### 理由

1. **多集群原生**：kind 可以拉多个集群，模拟生产多集群拓扑
2. **Docker-in-Docker 支持好**：用 `extraMounts` 把宿主机 docker.sock 共享进去
3. **生产一致性高**：kind 用 kubeadm 启动，与生产 K8s 行为一致
4. **CI 友好**：可在 GitHub Actions 跑通

### 否决方案

- **minikube**：单 VM，不支持多集群
- **k3d**：多集群支持好，但 K3s 与标准 K8s 有差异（去掉了一些 in-tree 特性）
- **Docker Desktop 内置 K8s**：单集群，且只支持本机

### 后果

- 多集群占资源较多（每个集群 control-plane + 2 node，~6 节点）
- Windows 环境下 kind + Docker Desktop 配合可能有性能问题
- 必须在 README 写明"最低 16GB 内存推荐"

---

## 决策统计

| 类别 | 已做决策数 |
|---|---|
| GitOps / CD | 1 |
| CI | 1 |
| IaC | 1 |
| IAM | 1 |
| 监控 | 1 |
| 多集群 | 1 |
| 灾备 | 1 |
| 供应链 | 1 |
| 告警 | 1 |
| 混沌 | 1 |
| 本地开发 | 1 |
| **合计** | **11** |

---

## 待决（未来可能做）

- ADR-012：内部开发者门户（Backstage vs Port vs 自建）—— 暂不急，Phase 4 再议
- ADR-013：服务网格（Istio vs Linkerd vs Cilium Service Mesh）—— 暂以"可选"处理
- ADR-014：密钥管理（Vault vs Sealed Secrets + External Secrets）—— 倾向 Vault
- ADR-015：镜像 GC 策略 —— 跟随 Harbor 默认
