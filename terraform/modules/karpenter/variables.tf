variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod"
  }
}

variable "cluster_name" {
  description = "EKS cluster name (used to scope the eks:DescribeCluster permission)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (used in IRSA trust policy principal)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider without https:// (used in IRSA trust policy conditions)"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes — Karpenter passes this role to launched EC2 instances"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
