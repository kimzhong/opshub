# Crossplane 骨架：应用自服务 IaC

> 用途：业务团队通过简单 Claim 申请数据库、缓存、消息队列、对象存储，**不用懂云**。
> 平台团队：维护 Composition + Provider（Terraform/Terraform-like）。
> 业务团队：写简单的 `XxxClaim`，Crossplane 自动对账真实资源。

## 设计哲学

```
业务团队：
  "我需要一个 prod 环境的 medium Postgres"
  ↓
写一个 Claim（5 行 YAML）：
  apiVersion: opshub.io/v1alpha1
  kind: PostgresDatabase
  spec:
    size: medium
    environment: prod
  ↓
Crossplane 自动：
  - 创建 RDS 实例（规格自动选）
  - 创建安全组
  - 创建 Secret 包含连接信息
  - 持续对账（drift detection）
  ↓
业务应用直接消费 Secret 里的连接串
```

## 边界

- **Terraform 管**：账号、VPC、托管 K8s、IAM 角色、镜像仓库（基础）
- **Crossplane 管**：业务需要的 RDS、Redis、RabbitMQ、S3 bucket（应用层）

## 实际目录

```
iac/crossplane/
├── providers.yaml             # Provider 资源 + ProviderConfig + AWS 凭据 Secret
├── compositions/
│   ├── postgres.yaml          # XPostgresDatabase（RDS PostgreSQL）
│   ├── redis.yaml             # XRedisCluster（ElastiCache）
│   ├── rabbitmq.yaml          # XRabbitMQCluster（Amazon MQ）
│   └── s3-bucket.yaml         # XBucket（S3 + KMS + 公开访问锁 + 跨区复制）
└── README.md                  # 本文件
```

## 快速开始

```bash
# 1. 安装 Crossplane Helm
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane --namespace crossplane-system --create-namespace

# 2. 创建 AWS 凭据 Secret（先用长 key，后续切换 IRSA）
kubectl create secret generic aws-credentials -n crossplane-system \
  --from-file=credentials=$HOME/.aws/credentials

# 3. 平台团队：安装 Provider + Composition
kubectl apply -f providers.yaml
kubectl apply -f compositions/postgres.yaml
kubectl apply -f compositions/redis.yaml
kubectl apply -f compositions/rabbitmq.yaml
kubectl apply -f compositions/s3-bucket.yaml

# 4. 验证 Provider 健康
kubectl get providers
# NAME                       HEALTHY PACKAGE                                       AGE
# provider-aws               True    xpkg.upbound.io/upbound/provider-aws:v0.47.0  1m
# provider-aws-rds           True    xpkg.upbound.io/upbound/provider-aws-rds       1m
# provider-aws-elasticache   True    ...                                              1m
# provider-aws-s3            True    ...                                              1m
# provider-aws-mq            True    ...                                              1m
```

## 已实现 Compositions

| 资源 | 业务 Claim kind | 后端 | 文件 |
|---|---|---|---|
| XPostgresDatabase | `PostgresDatabase` | AWS RDS PostgreSQL | `compositions/postgres.yaml` |
| XRedisCluster | `RedisCluster` | AWS ElastiCache | `compositions/redis.yaml` |
| XRabbitMQCluster | `RabbitMQCluster` | AWS Amazon MQ (RabbitMQ) | `compositions/rabbitmq.yaml` |
| XBucket | `Bucket` | AWS S3 + KMS + 公开锁 + CRR | `compositions/s3-bucket.yaml` |

## 业务团队示例 Claim

### 数据库

```yaml
apiVersion: opshub.io/v1alpha1
kind: PostgresDatabase
metadata:
  name: checkout-db
  namespace: team-checkout
spec:
  size: medium            # small/medium/large
  environment: prod
  region: regiona
  engineVersion: "15.4"
  multiAz: true
  backupRetentionDays: 14
```

### 缓存

```yaml
apiVersion: opshub.io/v1alpha1
kind: RedisCluster
metadata:
  name: checkout-cache
  namespace: team-checkout
spec:
  size: medium
  environment: prod
  region: regiona
  engineVersion: "7.0"
  multiAz: true
  backupRetentionDays: 7
```

### 消息队列

```yaml
apiVersion: opshub.io/v1alpha1
kind: RabbitMQCluster
metadata:
  name: order-mq
  namespace: team-order
spec:
  size: medium
  environment: prod
  region: regiona
  rabbitmqVersion: "3.13"
  multiAz: true
```

### 对象存储

```yaml
apiVersion: opshub.io/v1alpha1
kind: Bucket
metadata:
  name: checkout-assets
  namespace: team-checkout
spec:
  size: medium
  environment: prod
  region: regiona
  versioning: true
  encryption: kms         # 金融合规必须 kms
  publicAccess: false     # 金融场景必须 false
  lifecycleDays: 90       # 90 天后归档到 Glacier
  replication: true       # 跨区域复制
```

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| Provider 类型 | `upbound/provider-aws` 官方包 | 维护最活跃，覆盖最全 |
| Composition 写法 | Patch Set（不用 pipeline）| 简单场景够用，未来再升级 |
| 命名空间策略 | `crossplane-system` 系统级，业务 Claim 在各自 ns | 隔离 |
| 凭证 | 先用长 key 起步，**生产切 IRSA** | 避免长期 key |
| Drift 对账 | 默认开（5min） | 修复手抖 |
| 删除保护 | `deletionProtection: true`（Compositions 默认） | 防误删 |
| RabbitMQ 实现 | Amazon MQ（非自管） | 少运维、有 SLA |
| S3 加密 | 默认 KMS（金融合规）| AES256 不合规审计 |

## 安全考虑（默认开启）

- ✅ **AWS IRSA**（生产用，不是 long-lived AccessKey）
- ✅ **RDS publiclyAccessible: false**（仅内网）
- ✅ **SecurityGroup 限定 10.0.0.0/16**（仅 VPC 内访问）
- ✅ **storageEncrypted: true**（RDS 加密 / S3 KMS）
- ✅ **backupRetentionPeriod** 默认 7 天
- ✅ **deletionProtection: true**（防误删）
- ✅ **S3 publicAccessBlock: true**（防 S3 桶泄露）
- ✅ **S3 versioning + MFA delete**（防误删）
- ✅ **ElastiCache transitEncryption + atRestEncryption**

## 验证

```bash
# 看 Composite Resource 状态
kubectl get xpostgresdatabases
kubectl get xredisclusters
kubectl get xrabbitmqclusters
kubectl get xbuckets

# 看 Claim 视角
kubectl get postgresdatabase,rediscluster,rabbitmqcluster,bucket -A

# 看实际创建的 AWS 托管资源
kubectl get rdsinstance,replicationgroup,broker,bucket -n crossplane-system

# 看 Secret（连接信息）
kubectl get secret <name>-endpoint -n crossplane-system -o jsonpath='{.data.endpoint}' | base64 -d
```

## 与 ArgoCD 集成

业务 Claim 也应 GitOps 管理（推荐放业务仓库）：

```
业务 git repo: opshub-biz-manifests
└── apps/checkout-api/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── postgres-claim.yaml     # 业务声明
    ├── redis-claim.yaml        # 业务声明
    └── s3-claim.yaml           # 业务声明
```

ArgoCD 监听 Git 变更 → 自动 apply Claim → Crossplane 对账 → AWS 资源创建/更新。

## 待办（下一轮）

- [ ] Kafka / MSK Composition
- [ ] CloudFront / CDN Composition
- [ ] RDS 增强：只读副本、Cross-Region Replica
- [ ] 业务 ns NetworkPolicy 模板
- [ ] 业务 Claim 校验 admission（size × environment 矩阵）
- [ ] 把 Claim 模板放进 Backstage 软件目录
- [ ] Crossplane → Prometheus exporter（业务账单可观测）
