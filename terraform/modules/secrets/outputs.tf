output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key — referenced by External Secrets Operator"
  value       = aws_secretsmanager_secret.openai_api_key.arn
  sensitive   = true
}

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator (IRSA) — annotate the external-secrets-sa ServiceAccount with this value"
  value       = aws_iam_role.eso.arn
}
