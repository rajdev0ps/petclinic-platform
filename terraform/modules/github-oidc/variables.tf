variable "github_repo" {
  description = "Primary GitHub repository allowed to assume the role — format: 'owner/repo'"
  type        = string
}

variable "additional_github_repos" {
  description = "Additional GitHub repositories allowed to assume the role — same format as github_repo"
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "Name of the IAM role created for GitHub Actions OIDC federation"
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider. Set false if the provider already exists in the account (only one allowed per account)."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider — required when create_oidc_provider = false"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all created resources"
  type        = map(string)
  default     = {}
}
