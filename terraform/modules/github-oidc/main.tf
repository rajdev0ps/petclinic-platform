data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  oidc_host = "token.actions.githubusercontent.com"

  # Resolved provider ARN — either newly created or the one passed in.
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn

  # All repos allowed to assume this role — primary + any additional repos.
  # IAM StringEquals with a list evaluates as OR, so each subject is checked independently.
  subjects = concat(
    ["repo:${var.github_repo}:*"],
    [for repo in var.additional_github_repos : "repo:${repo}:*"]
  )
}

# ─── OIDC Provider ────────────────────────────────────────────────────────────
# One provider per AWS account. Use create_oidc_provider = false in the second
# environment (prod) and pass the ARN from the dev output or a data source.
#
# Thumbprints cover both GitHub root CAs (original + post-2023 rotation).
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.oidc_host}"
  client_id_list  = ["sts.amazonaws.com", "https://github.com/rajdev0ps"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea6",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = merge(var.tags, { Name = "github-actions-oidc" })
}

# ─── IAM Role ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name        = var.role_name
  description = "Assumed by GitHub Actions in ${var.github_repo} via OIDC - ECR push only"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_host}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.oidc_host}:sub" = "repo:rajdev0ps/*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = var.role_name })
}

# ─── ECR Push Policy ──────────────────────────────────────────────────────────
# Permissions scoped to petclinic ECR repositories only.
# ecr:GetAuthorizationToken is account-level and requires resource = "*".
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/petclinic-*"
      }
    ]
  })
}
