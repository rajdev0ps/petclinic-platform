locals {
  name_prefix = "${var.project}-${var.environment}"
  # Dev:  petclinic-dev.example.com
  # Prod: petclinic.example.com
  app_subdomain = var.environment == "prod" ? var.project : "${var.project}-${var.environment}"
  app_fqdn      = "${local.app_subdomain}.${var.domain_name}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ─── ACM Certificate ─────────────────────────────────────────────────────────
# Wildcard cert covers *.example.com and example.com (SAN).
# Validated via DNS — CNAME records are written into the Route 53 zone.
# ACM must be in the same region as the ALB.
#
# The aws.dns provider alias is used for all Route 53 operations.
# For single-account deployments it resolves to the same credentials as the default provider.
# For cross-account DNS, configure assume_role in the aws.dns provider in providers.tf.

resource "aws_acm_certificate" "main" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-acm-cert"
  })
}

# ─── ACM DNS Validation Records ───────────────────────────────────────────────
# Creates CNAME records in the hosted zone (account 025760030746) to prove
# domain ownership for the ACM certificate.

locals {
  # Key by static domain_name so keys are known at plan time for for_each
  cert_validation_records = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
}

resource "aws_route53_record" "cert_validation" {
  provider = aws.dns

  for_each = (var.zone_id != "" && !can(regex("^Z0123456789", var.zone_id))) ? local.cert_validation_records : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  count                   = (var.zone_id != "" && !can(regex("^Z0123456789", var.zone_id))) ? 1 : 0
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ─── Route 53 A Record → ALB (PETPLAT-31) ────────────────────────────────────
# Alias A record: {app_fqdn} → ALB
#
# Skipped on initial apply (alb_dns_name defaults to "").
# Populate alb_dns_name and alb_zone_id in terraform.tfvars after:
#   1. Running scripts/install-lb-controller.sh
#   2. Applying k8s/base/ingress/ingress.yaml
#   3. kubectl get ingress petclinic-ingress -n petclinic-{env} \
#        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Then re-run: terraform apply
#
# Regional ALB hosted zone IDs: us-east-1=Z35SXDOTRQ7X7K, eu-west-1=Z32O12XQLNTSW2,
# eu-central-1=Z215JYRZR1TBD5 (full list: https://docs.aws.amazon.com/general/latest/gr/elb.html)

resource "aws_route53_record" "app" {
  provider = aws.dns
  count    = (var.alb_dns_name != "" && var.alb_zone_id != "") ? 1 : 0

  zone_id = var.zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ─── LB Controller IAM Policy ────────────────────────────────────────────────
# Full permission set required by the AWS Load Balancer Controller v2.x.
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/lbc-manifest.html
# Policy is scoped where possible; broad actions on * are required for tag-based
# conditional access patterns used by the controller.

data "aws_iam_policy_document" "lb_controller" {
  statement {
    sid     = "CreateServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid    = "EC2ReadAccess"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ELBReadAccess"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CertificateManagerAccess"
    effect = "Allow"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMCertAccess"
    effect = "Allow"
    actions = [
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CognitoAccess"
    effect  = "Allow"
    actions = ["cognito-idp:DescribeUserPoolClient"]
    resources = ["*"]
  }

  # WAFv2 and WAF Regional statements omitted for this POC — WAF is not used.
  # To add WAF in production: create an aws_wafv2_web_acl resource, then add:
  #   wafv2:GetWebACL, GetWebACLForResource, ListResourcesForWebACL, AssociateWebACL, DisassociateWebACL
  #   waf-regional:GetWebACL, GetWebACLForResource, AssociateWebACL, DisassociateWebACL
  # Scope both statements to the specific Web ACL ARN, not resources = ["*"].

  # Shield read-only: write actions (CreateProtection, DeleteProtection) removed for this POC.
  # Shield Advanced is a paid service; enabling it requires explicit opt-in. Re-add write actions
  # and scope to the ALB ARN if Shield integration is needed in production.
  statement {
    sid    = "ShieldAccess"
    effect = "Allow"
    actions = [
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EC2SGIngress"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
    # Restrict to security groups owned by this cluster (defense in depth, HIGH-003)
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid     = "EC2SGCreate"
    effect  = "Allow"
    actions = ["ec2:CreateSecurityGroup"]
    resources = ["*"]
  }

  statement {
    sid     = "EC2TagOnCreate"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "EC2TagManage"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid     = "EC2SGDelete"
    effect  = "Allow"
    actions = ["ec2:DeleteSecurityGroup"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBCreate"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBListenerRule"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
    ]
    resources = ["*"]
  }

  # Allows AddTags during CreateLoadBalancer / CreateTargetGroup when the
  # cluster tag is part of the create request. Without this, the controller
  # cannot tag a brand-new ALB (the resource tag doesn't exist yet, so the
  # ELBTagManage statement below never matches).
  statement {
    sid    = "ELBTagOnCreateAction"
    effect = "Allow"
    actions = ["elasticloadbalancing:AddTags"]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values   = ["CreateTargetGroup", "CreateLoadBalancer"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBTagManage"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBListenerTagManage"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]
    # Restrict to listeners/rules belonging to cluster-owned load balancers (HIGH-002)
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBModify"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ELBTargetRegistration"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }

  statement {
    sid    = "ELBListenerManage"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${local.name_prefix}-lb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller to manage ALBs and NLBs"
  policy      = data.aws_iam_policy_document.lb_controller.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-controller-policy"
  })
}

# ─── LB Controller IRSA Role ──────────────────────────────────────────────────
# PETPLAT-29: IAM Role for Service Account scoped to the LB controller SA.
# Service account: aws-load-balancer-controller in kube-system namespace.
# See: docs/technical-spec.md#irsa-roles

data "aws_iam_policy_document" "lb_controller_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}
