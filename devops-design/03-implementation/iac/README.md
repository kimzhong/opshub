# OpsHub IaC 资产

> 平台团队使用，业务团队不需要直接接触。
> 目标：所有云资源和应用层资源都可声明、可 GitOps、可对账。

## 边界

```
┌─────────────────────────────────────────────────────────────┐
│ Terraform (基础)            │ Crossplane (应用)             │
├─────────────────────────────────────────────────────────────┤
│ AWS Account / IAM / Org     │ RDS PostgreSQL                │
│ VPC / Subnet / NAT          │ ElastiCache Redis             │
│ EKS / 托管 K8s              │ Amazon MQ RabbitMQ            │
│ S3 (基础日志/备份桶)        │ S3 (业务桶)                   │
│ KMS / ACM / Route53         │ (未来) MSK Kafka / CDN        │
└─────────────────────────────────────────────────────────────┘
```

| 层 | 工具 | 负责 | 文件 |
|---|---|---|---|
| 基础设施 | Terraform | 平台 SRE | `terraform/` |
| 应用自服务 | Crossplane | 平台 SRE 维护 Composition，业务团队写 Claim | `crossplane/` |

## 目录

```
iac/
├── README.md                 # 本文件
├── terraform/                # 基础架构（账号/VPC/托管K8s）
│   ├── main.tf
│   ├── variables.tf
│   └── README.md
└── crossplane/               # 应用层自服务（数据库/缓存/队列/存储）
    ├── providers.yaml
    ├── compositions/
    │   ├── postgres.yaml
    │   ├── redis.yaml
    │   ├── rabbitmq.yaml
    │   └── s3-bucket.yaml
    └── README.md
```

## 选型理由

- **Terraform 选型**：行业标准，AWS provider 维护最活跃，State 托管推荐用 S3 + DynamoDB 锁
- **Crossplane 选型**：原生 K8s，GitOps 友好（直接 kubectl apply），和 ArgoCD 同生态；业务 Claim 可以放在业务仓库由 ArgoCD 同步
- **拒绝 Pulumi/CDK**：团队学习曲线 + 与 GitOps 生态不如 HCL/YAML 自然
- **拒绝自研 IaC**：维护成本不划算

## 部署顺序

```
1. Terraform 一次性 apply（账号/VPC/EKS/基础IAM）
       ↓
2. ArgoCD 安装（GitOps 启动）
       ↓
3. Crossplane Helm 安装
       ↓
4. Crossplane Provider 部署（providers.yaml）
       ↓
5. Crossplane Composition 部署（compositions/*.yaml）
       ↓
6. 业务团队写 Claim（被 ArgoCD 自动同步）
```

## 安全基线（全部默认开启）

- [x] AWS IRSA（生产用 OIDC，避免 long-lived key）
- [x] 所有 RDS 加密 at rest + in transit
- [x] 所有 S3 桶 public access block
- [x] 所有 S3 桶 KMS 加密（金融合规）
- [x] 所有 S3 桶 versioning + MFA delete
- [x] 所有 SG 仅内网（10.0.0.0/8）
- [x] deletionProtection 防误删
- [x] 跨区域复制可选开启（DR 用途）

## 与平台其他组件的关系

| 组件 | 与 IaC 关系 |
|---|---|
| ArgoCD | 监听 `iac/` 目录变化，自动 apply Provider/Composition |
| Prometheus | 监控 Crossplane 控制器和 AWS 资源指标 |
| Velero | 备份 Crossplane CRD 和业务 Claim |
| Keycloak | 管理员通过 SSO 登录 AWS Console（IRSA 配合） |

## 待办

- [ ] Terraform state 后端（S3 + DynamoDB lock）
- [ ] Terraform 模块化拆分（network/eks/iam）
- [ ] MSK Kafka / CloudFront / SQS Composition
- [ ] IaC → CI Pipeline（PR 预览 plan）
- [ ] 业务账单看板（按 Claim 计费）
- [ ] Backstage 集成（业务团队通过 UI 申请）
