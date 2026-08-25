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

# Route 53 provider alias.
# For single-account deployments (all resources in one account): no assume_role — both
# providers use the same credentials.
# For cross-account DNS (Route 53 in a separate account): uncomment the assume_role block
# and add a dns_account_id variable with the target account ID.
provider "aws" {
  alias  = "dns"
  region = var.aws_region

  # Cross-account DNS — uncomment if Route 53 is in a different AWS account:
  # assume_role {
  #   role_arn = "arn:aws:iam::${var.dns_account_id}:role/TerraformDNSRole"
  # }
}
