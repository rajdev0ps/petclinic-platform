locals {
  bucket_name = "petclinic-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "aws_caller_identity" "current" {}

# ─── S3 State Bucket ─────────────────────────────────────────────────────────
# Versioning preserves every state revision — required for point-in-time recovery.
# Public access is blocked at the bucket level (separate from IAM).
# SSE-S3 is sufficient for state; upgrade to SSE-KMS if compliance requires it.

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = local.bucket_name
    Project     = "petclinic"
    ManagedBy   = "terraform"
    Description = "Terraform remote state for petclinic platform"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ─── DynamoDB Lock Table ─────────────────────────────────────────────────────
# PAY_PER_REQUEST: no capacity planning needed — lock table is extremely low traffic.

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "petclinic-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Name      = "petclinic-terraform-locks"
    Project   = "petclinic"
    ManagedBy = "terraform"
  }
}
