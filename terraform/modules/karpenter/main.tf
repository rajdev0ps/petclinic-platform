data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  # Extract role name from ARN (handles path-qualified ARNs like arn:aws:iam::...:role/path/name)
  node_role_name = element(split("/", var.node_role_arn), length(split("/", var.node_role_arn)) - 1)

  default_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── Karpenter Controller IRSA Role ──────────────────────────────────────────

data "aws_iam_policy_document" "karpenter_trust" {
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
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "${local.name_prefix}-karpenter-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_trust.json

  tags = merge(local.default_tags, var.tags, { Name = "${local.name_prefix}-karpenter-role" })
}

data "aws_iam_policy_document" "karpenter" {
  # Read-only describe actions — safe to allow on * (no mutating operations)
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  # Instance creation — require karpenter.sh/nodepool tag in the launch request
  # so Karpenter cannot be used to launch arbitrary untagged EC2 instances.
  statement {
    sid    = "EC2CreateInstances"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Terminate ONLY Karpenter-managed instances (tagged with cluster discovery tag).
  # Prevents Karpenter controller from terminating unrelated EC2 instances.
  statement {
    sid     = "EC2TerminateInstances"
    effect  = "Allow"
    actions = ["ec2:TerminateInstances"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  # Launch template create — require cluster discovery tag in the request
  statement {
    sid     = "EC2CreateLaunchTemplate"
    effect  = "Allow"
    actions = ["ec2:CreateLaunchTemplate"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  # Launch template delete — scoped to Karpenter-owned templates only
  statement {
    sid     = "EC2DeleteLaunchTemplate"
    effect  = "Allow"
    actions = ["ec2:DeleteLaunchTemplate"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  # CreateTags — restricted to requests that include the Karpenter nodepool tag
  statement {
    sid     = "EC2CreateTags"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Scoped to the node IAM role only — prevents privilege escalation via PassRole
  statement {
    sid       = "PassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]
  }

  statement {
    sid       = "SSMParameter"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:*:parameter/aws/service/*"]
  }

  statement {
    sid       = "PricingProducts"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # Minimum SQS actions needed for interruption queue — scoped to this queue only
  statement {
    sid    = "SQSPermissions"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }

  statement {
    sid       = "EKSDescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }
}

resource "aws_iam_policy" "karpenter" {
  name        = "${local.name_prefix}-karpenter-policy"
  description = "IAM policy for Karpenter controller"
  policy      = data.aws_iam_policy_document.karpenter.json

  tags = merge(local.default_tags, var.tags)
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# ─── Karpenter Node Instance Profile ─────────────────────────────────────────
# Wraps the existing node IAM role so Karpenter-launched EC2 instances get the
# same permissions as managed node group nodes. Name is referenced by EC2NodeClass CRD.

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = local.node_role_name

  tags = merge(local.default_tags, var.tags, { Name = "${local.name_prefix}-karpenter-node-profile" })
}

# ─── SQS Interruption Queue ───────────────────────────────────────────────────

resource "aws_sqs_queue" "interruption" {
  name                       = "${local.name_prefix}-karpenter"
  message_retention_seconds  = 300
  visibility_timeout_seconds = 1200 # 20 minutes

  tags = merge(local.default_tags, var.tags, { Name = "${local.name_prefix}-karpenter" })
}

# Without this policy EventBridge can route the rules but messages never reach the queue
data "aws_iam_policy_document" "sqs_policy" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.sqs_policy.json
}

# ─── EventBridge Rules → SQS ─────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name_prefix}-karpenter-spot-interruption"
  description = "Karpenter: EC2 Spot interruption warnings"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = merge(local.default_tags, var.tags)
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${local.name_prefix}-karpenter-rebalance"
  description = "Karpenter: EC2 instance rebalance recommendations"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = merge(local.default_tags, var.tags)
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${local.name_prefix}-karpenter-instance-state"
  description = "Karpenter: EC2 instance state-change notifications"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })

  tags = merge(local.default_tags, var.tags)
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "${local.name_prefix}-karpenter-scheduled-change"
  description = "Karpenter: AWS Health scheduled change events for EC2"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
    detail = {
      service           = ["EC2"]
      eventTypeCategory = ["scheduledChange"]
    }
  })

  tags = merge(local.default_tags, var.tags)
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule      = aws_cloudwatch_event_rule.scheduled_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}
