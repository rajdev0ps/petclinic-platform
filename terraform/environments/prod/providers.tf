provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Route 53 provider alias — same account as the main provider (single-account deployment).
# See terraform/environments/dev/providers.tf for cross-account DNS instructions.
provider "aws" {
  alias  = "dns"
  region = var.aws_region

  # Cross-account DNS — uncomment if Route 53 is in a different AWS account:
  # assume_role {
  #   role_arn = "arn:aws:iam::${var.dns_account_id}:role/TerraformDNSRole"
  # }
}
