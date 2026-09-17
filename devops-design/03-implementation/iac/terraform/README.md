# Terraform 基础资源骨架

> 用途：管理公有云基础资源（VPC、托管 K8s、数据库、对象存储、网络）。
> 边界：只管"基础"层；应用层 RDS / Redis 用 Crossplane 给业务团队自助。

## 推荐目录结构

```
iac/terraform/
├── modules/                 # 可复用模块
│   ├── network/             # VPC / 子网 / NAT
│   ├── eks/                 # EKS 集群
│   ├── rds/                 # 托管数据库
│   └── s3/                  # 备份桶
├── envs/                    # 环境实例化
│   ├── prod/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── staging/
├── backend.tf               # state 后端配置
├── versions.tf              # provider / terraform 版本
├── variables.tf             # 通用变量
├── main.tf                  # 通用模块编排
└── README.md
```

## 快速开始

```bash
# 1. 准备后端（首次）
cd iac/terraform
terraform init -backend-config="bucket=opshub-tfstate" \
                -backend-config="key=infra/terraform.tfstate" \
                -backend-config="region=us-east-1" \
                -backend-config="dynamodb_table=opshub-tflock" \
                -backend-config="encrypt=true"

# 2. 规划
terraform plan -var-file=envs/prod/terraform.tfvars

# 3. 应用（推荐 PR 流程 + Atlantis/Spacelift）
terraform apply -var-file=envs/prod/terraform.tfvars
```

## 安全最佳实践

- ✅ **State 加密 + DynamoDB 锁**（已配置）
- ✅ **敏感变量走 Secrets Manager / Vault**，不写 tfvars
- ✅ **PR 流程**：所有变更通过 PR + Code Review
- ✅ **Plan + Apply 分离**：本地/CI 仅 plan，apply 由 Spacelift/Atlantis
- ✅ **OIDC for CI/CD**：避免长期 AccessKey

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| State 后端 | S3 + DynamoDB 锁 | 业界标准、便宜、可靠 |
| 模块管理 | 单独 `modules/` 目录 | 跨环境复用 |
| 环境隔离 | 独立 state（`envs/prod/`、`envs/staging/`）| 防止误操作 |
| 网络 | 3 AZ + 独立 NAT | 生产高可用 |
| EKS | 托管 control plane + managed node group | 减少运维负担 |
| 备份 | S3 + Object Lock + 跨 region 复制 | 防勒索 + 跨 region DR |

## 与 Crossplane 的边界

- **Terraform 管**：账号级 / region 级 / VPC / 托管 K8s / IAM（基础）
- **Crossplane 管**：应用需要的 RDS 实例 / Redis / S3 bucket（自助）

## 待办

- [ ] 拆分为 modules（当前是单文件）
- [ ] 添加 GitHub Actions / Atlantis pipeline
- [ ] 添加 policy 检查（tflint / tfsec / OPA）
- [ ] 跨 region DR 完整配置（当前只有 S3 replication）
