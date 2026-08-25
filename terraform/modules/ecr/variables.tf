variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "service_names" {
  description = "List of microservice names — one ECR repository is created per entry"
  type        = list(string)
  default = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must contain at least one service."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability: MUTABLE for dev (allows re-pushing), IMMUTABLE for prod (prevents overwrite)"
  type        = string

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images are expired"
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}

variable "tagged_keep_count" {
  description = "Maximum number of tagged images to keep per repository"
  type        = number
  default     = 10

  validation {
    condition     = var.tagged_keep_count >= 1 && var.tagged_keep_count <= 100
    error_message = "tagged_keep_count must be between 1 and 100."
  }
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
