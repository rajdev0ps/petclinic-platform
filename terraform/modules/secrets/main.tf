locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── Customer-Managed KMS Key for Secrets Manager ────────────────────────────
# CMK enables: on-demand rotation, per-key CloudTrail audit, explicit key deletion,
# and compliance with frameworks that prohibit AWS-managed key usage (PCI-DSS, SOC 2).

resource "aws_kms_key" "secrets" {
  description             = "CMK for Secrets Manager secrets in ${local.name_prefix}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-secrets-key"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ─── OpenAI API Key Secret (PETPLAT-33) ──────────────────────────────────────
# Stores the OpenAI API key for genai-service in Secrets Manager as plaintext.
# Value is injected via var.openai_api_key (sensitive) — never hardcoded.

resource "aws_secretsmanager_secret" "openai_api_key" {
  name        = "petclinic/${var.environment}/openai-api-key"
  description = "OpenAI API key for genai-service in ${local.name_prefix}"
  kms_key_id  = aws_kms_key.secrets.arn

  # 0 = immediate deletion (allows re-create with same name after destroy in dev).
  # 30-day recovery window in prod prevents accidental permanent loss.
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-openai-api-key"
    Service = "genai-service"
  })
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}

# ─── ESO IRSA Trust Policy (PETPLAT-37) ──────────────────────────────────────
# Trust relationship scoped to the specific K8s ServiceAccount (external-secrets-sa)
# in the external-secrets namespace, using two StringEquals conditions to prevent
# confused deputy attacks.

data "aws_iam_policy_document" "eso_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name_prefix}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
  description        = "IRSA role for External Secrets Operator in ${local.name_prefix}"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eso-role"
  })
}

# ─── ESO IAM Permissions (PETPLAT-37) ────────────────────────────────────────
# Scoped to petclinic/* secrets only — ESO cannot read unrelated secrets.
# KMS Decrypt is restricted via kms:ViaService to only allow decryption
# when called through the Secrets Manager service (required for CMK-encrypted secrets).

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:petclinic/*"
    ]
  }

  # Required when secrets are encrypted with a customer-managed KMS key (CMK).
  # Currently unused — all petclinic secrets use the AWS-managed key (aws/secretsmanager),
  # which does not require an explicit kms:Decrypt IAM statement. This statement is included
  # so that migrating any secret to a CMK in the future requires no IAM changes.
  #
  # The kms:ViaService condition restricts the permission to calls originating from the
  # Secrets Manager service endpoint only — preventing direct use of the KMS key outside
  # of secret retrieval. The resource ARN uses key/* because the CMK ARN is not known at
  # module authoring time; this is the AWS-recommended pattern when the key ID is dynamic.
  statement {
    sid    = "KMSDecryptViaSecretsManager"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.secrets.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${local.name_prefix}-eso-policy"
  description = "Secrets Manager read access for External Secrets Operator in ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.eso_permissions.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eso-policy"
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
