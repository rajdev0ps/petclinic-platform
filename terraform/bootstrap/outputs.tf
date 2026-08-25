output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state — use in backend.hcl for all environments"
  value       = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking — use in backend.hcl for all environments"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "backend_hcl_content" {
  description = "Ready-to-paste backend.hcl content for environment directories"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.tfstate.bucket}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
    encrypt        = true
  EOT
}
