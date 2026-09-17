# Variables for opshub 基础资源
# 用法：cp terraform.tfvars.example terraform.tfvars 并填值

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment: prod / staging / dev"
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be prod, staging, or dev."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (platform management cluster)"
  default     = "opshub-mgmt"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.30"
}

variable "business_cluster_name" {
  type        = string
  description = "业务集群名（region A）"
  default     = "opshub-biz-regiona"
}

variable "business_cluster_name_b" {
  type        = string
  description = "业务集群名（region B / DR）"
  default     = "opshub-biz-regionb"
}

variable "dr_region" {
  type        = string
  description = "DR region"
  default     = "us-west-2"
}

variable "domain_name" {
  type        = string
  description = "内部域名（用于 *.ops.internal 证书）"
  default     = "ops.internal"
}

variable "keycloak_admin_password" {
  type        = string
  description = "Keycloak admin password"
  sensitive   = true
  default     = ""
}
