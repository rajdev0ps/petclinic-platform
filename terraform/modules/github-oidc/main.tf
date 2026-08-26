# ─── GitHub OIDC Module ───────────────────────────────────────────────────────
# Establishes an IAM OpenID Connect identity provider for GitHub Actions and
# provisions an IAM role that can be assumed by workflows in specified repos.

locals {
  oidc_host         = "token.actions.githubusercontent.com"
  oidc_provider_arn = aws_iam_openid_connect_provider.github[0].arn
}

# ─── OIDC Provider ────────────────────────────────────────────────────────────
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
          StringLike = {
            "${local.oidc_host}:sub" = "repo:rajdev0ps*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = var.role_name })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ─── IAM Policy: ECR Push Only ────────────────────────────────────────────────
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.name

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
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/petclinic-*"
      }
    ]
  })
}
