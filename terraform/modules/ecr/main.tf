data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.tagged_keep_count} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.tagged_keep_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ─── ECR Repositories ─────────────────────────────────────────────────────────
# One repository per service, namespaced as petclinic-{env}/{service}.

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  name                 = "${local.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name      = "${local.name_prefix}/${each.key}"
    Component = "registry"
    Service   = each.key
  })
}

# ─── Lifecycle Policies ───────────────────────────────────────────────────────
# Keeps last N tagged images and expires untagged after N days.

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name
  policy     = local.lifecycle_policy
}

# ─── Repository Policies ──────────────────────────────────────────────────────
# Deny image pulls from outside this AWS account. Defense-in-depth against
# cross-account access even if IAM policies are misconfigured.

resource "aws_ecr_repository_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOutsideAccount"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })
}
