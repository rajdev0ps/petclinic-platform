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
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Pass via TF_VAR_openai_api_key env var — never hardcode or commit."
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS module — used to build the ESO IRSA trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL from the EKS module (without https://) — used as the IAM condition key in the trust policy."
  type        = string
}

variable "tags" {
  description = "Additional tags to merge into all resource tags"
  type        = map(string)
  default     = {}
}
