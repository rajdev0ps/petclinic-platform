variable "aws_region" {
  description = "AWS region for all resources. Must match the region used in bootstrap and backend.hcl."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Pass via TF_VAR_openai_api_key env var — never hardcode or commit."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "Email address for AWS Budget cost alert notifications (50%/80%/100% of $100/month)"
  type        = string
}

variable "domain_name" {
  description = "Root domain name with an existing Route 53 public hosted zone (e.g. example.com)."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone ID for domain_name."
  type        = string
  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,32}$", var.zone_id))
    error_message = "zone_id must start with 'Z' followed by uppercase letters and digits."
  }
}

variable "alb_dns_name" {
  description = "ALB DNS hostname created by the LB controller. Leave empty on first apply."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB for Route 53 alias record."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository for the Spring Petclinic Microservices app in 'owner/repo' format."
  type        = string
}

variable "additional_github_repos" {
  description = "Additional GitHub repositories allowed to assume the ECR push role."
  type        = list(string)
  default     = []
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API server. Restrict to operator/VPN IPs."
  type        = list(string)
}
