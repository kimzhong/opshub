# OpsHub 基础资源 - Terraform 骨架
# 用途：管理公有云基础资源（VPC、RDS、ACK/TKE/EKS 等）
# 推荐通过 Terraform Cloud / Atlantis / Spacelift 跑，避免本地 state
# 边界：只管"基础"层；应用层用 Crossplane

terraform {
  required_version = ">= 1.7.0"

  # 生产推荐用 S3 / OSS 后端；PoC 用 local
  backend "s3" {
    bucket         = "opshub-tfstate"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"  # 替换为实际 region
    encrypt        = true
    dynamodb_table = "opshub-tflock"  # state 锁
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "OpsHub"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# ===== 变量 =====
variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment (prod/staging/dev)"
  default     = "prod"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR"
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
  default     = "opshub-mgmt"
}

# ===== 数据源 =====
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ===== 网络 =====
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "opshub-${var.environment}"
  cidr = var.vpc_cidr

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false  # 生产每个 AZ 一个 NAT
  enable_dns_hostnames    = true
  enable_dns_support      = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ===== 平台管理集群 (EKS) =====
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # OIDC for IRSA（IAM Role for Service Accounts）
  cluster_identity_providers = {
    github = {
      provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      audience     = "sts.amazonaws.com"
    }
  }

  eks_managed_node_groups = {
    mgmt_main = {
      min_size       = 3
      max_size       = 10
      desired_size   = 3
      instance_types = ["m6i.xlarge"]
      capacity_type  = "ON_DEMAND"
      subnet_ids     = module.vpc.private_subnets
      labels = {
        workload = "platform"
      }
    }
  }

  tags = {
    Environment = var.environment
    Role        = "platform-management"
  }
}

# ===== 数据库（RDS for Keycloak 等）=====
resource "aws_db_subnet_group" "platform" {
  name       = "opshub-${var.environment}"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "opshub-rds-${var.environment}"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "keycloak" {
  identifier     = "opshub-keycloak-${var.environment}"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.r6g.large"
  allocated_storage = 50

  db_name  = "keycloak"
  username = "keycloak"
  password = random_password.keycloak_db.result

  db_subnet_group_name   = aws_db_subnet_group.platform.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 30
  multi_az                = true
  deletion_protection     = true
  skip_final_snapshot     = false

  tags = {
    Service = "keycloak"
  }
}

# 随机密码（生产用 Secrets Manager）
resource "random_password" "keycloak_db" {
  length  = 32
  special = false
}

# ===== 镜像存储（S3 for Velero backups / Harbor）=====
module "backup_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "opshub-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"

  versioning = {
    enabled = true
  }

  lifecycle_rule = [{
    id      = "expire-old-backups"
    enabled = true
    expiration = {
      days = 90
    }
    noncurrent_version_expiration = {
      days = 30
    }
  }]

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # Object Lock（WORM，防勒索软件）
  object_lock_configuration = {
    object_lock_enabled = true
    rule = {
      default_retention = {
        mode = "COMPLIANCE"
        days = 30
      }
    }
  }

  tags = {
    Purpose = "velero-backups"
  }
}

# ===== 跨 region 复制 =====
# 生产推荐启用
resource "aws_s3_bucket_replication_configuration" "backup_dr" {
  count = var.environment == "prod" ? 1 : 0

  bucket = module.backup_bucket.s3_bucket_id
  role   = aws_iam_role.backup_replication[0].arn

  rule {
    id     = "dr-region-replication"
    status = "Enabled"

    destination {
      bucket        = "opshub-backups-dr-${var.environment}"
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_iam_role" "backup_replication" {
  count = var.environment == "prod" ? 1 : 0
  name  = "opshub-backup-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# ===== 输出 =====
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "keycloak_db_endpoint" {
  value     = aws_db_instance.keycloak.endpoint
  sensitive = true
}

output "backup_bucket" {
  value = module.backup_bucket.s3_bucket_id
}
