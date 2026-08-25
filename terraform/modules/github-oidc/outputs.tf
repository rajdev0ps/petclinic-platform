output "role_arn" {
  description = "ARN of the GitHub Actions IAM role — set as AWS_ROLE_ARN secret in the app repo"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider — pass as oidc_provider_arn in the prod env when create_oidc_provider = false"
  value       = local.oidc_provider_arn
}
