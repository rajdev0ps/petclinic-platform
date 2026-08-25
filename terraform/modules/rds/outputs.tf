output "endpoint" {
  description = "RDS instance endpoint hostname (without port)"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "port" {
  description = "RDS instance port (3306)"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "secret_arn" {
  description = "Secrets Manager ARN for RDS credentials — used by External Secrets Operator"
  value       = aws_secretsmanager_secret.rds_credentials.arn
  sensitive   = true
}

output "connection_string" {
  description = "JDBC connection string for Spring datasource (use in K8s ConfigMap)"
  value       = "jdbc:mysql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/petclinic"
  sensitive   = true
}
