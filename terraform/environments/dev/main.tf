module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  # VPC Network Design — see docs/technical-spec.md#vpc-network-design
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["${var.aws_region}a", "${var.aws_region}b"]

  tags = {
    Component = "networking"
  }
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  # EKS Cluster — see docs/technical-spec.md#eks-cluster
  cluster_version = "1.35"
  subnet_ids      = module.vpc.public_subnet_ids
  cluster_sg_id   = module.vpc.eks_cluster_sg_id
  node_sg_id      = module.vpc.eks_node_sg_id

  # Node group — t4g.small ARM64 (100% AWS Free Tier eligible, 5 nodes x 2GB)
  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_min_size       = 5
  node_max_size       = 10
  node_desired_size   = 5
  node_disk_size      = 20

  # Restrict public EKS API to known operator IPs only.
  # ArgoCD runs in-cluster (private access). CI only pushes to ECR — no kubectl needed.
  # Add additional CIDRs for other team members via var.eks_public_access_cidrs.
  public_access_cidrs = var.eks_public_access_cidrs

  tags = {
    Component = "compute"
  }
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  # ECR — see docs/technical-spec.md#ecr-container-registry
  image_tag_mutability = "MUTABLE"

  tags = {
    Component = "registry"
  }
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  # RDS — see docs/technical-spec.md#rds-database
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  # db.t4g.micro is RDS free-tier eligible (750 hrs/month for 12 months)
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 20
  multi_az              = false

  # Dev: 1 day backup retention for Free Tier compliance, skip final snapshot for easy teardown
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Component = "database"
  }
}

# ─── Secrets Management (PETPLAT-33, PETPLAT-37) ────────────────────────────
# Creates the OpenAI API key secret and the ESO IRSA role.
# Pass the OpenAI key via: export TF_VAR_openai_api_key="sk-..."

module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment

  openai_api_key    = var.openai_api_key
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  tags = {
    Component = "secrets"
  }
}

# ─── DNS & Ingress (PETPLAT-28 through PETPLAT-32) ───────────────────────────
# Requires:
#   - var.domain_name: a registered domain with a Route 53 hosted zone in this account
#   - var.zone_id: hosted zone ID (retrieve after purchasing domain)
#   - var.alb_dns_name / var.alb_zone_id: populated AFTER running install-lb-controller.sh
#     and applying k8s/base/ingress/ingress.yaml; leave empty on first apply.
#
# Two-phase apply:
#   Phase 1 (initial): apply with alb_dns_name="" — creates ACM cert + LB controller IAM
#   Phase 2 (post-ingress): update terraform.tfvars with ALB details, re-apply to create A record

module "dns" {
  source = "../../modules/dns"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  zone_id     = var.zone_id

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  alb_dns_name = var.alb_dns_name
  alb_zone_id  = var.alb_zone_id

  tags = {
    Component = "dns"
  }
}

# ─── Karpenter (PETPLAT-73) ──────────────────────────────────────────────────
# IAM role (IRSA), node instance profile, SQS interruption queue, EventBridge rules.
# The instance profile name petclinic-dev-karpenter-node-profile is referenced by
# the EC2NodeClass CRD in k8s/argocd/karpenter/.

module "karpenter" {
  source = "../../modules/karpenter"

  project     = var.project
  environment = var.environment

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_role_arn

  tags = {
    Component = "autoscaling"
  }
}

# ─── AWS Budget Alert (PETPLAT-75) ───────────────────────────────────────────
# ACTUAL spend alerts — fires on real charges, not forecasts.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# ─── GitHub Actions OIDC Federation (PETPLAT-52) ─────────────────────────────
# Creates the GitHub OIDC provider (once per account) and an IAM role that
# the build-push.yml workflow in the app repo assumes via web identity.
# The OIDC provider is account-scoped — prod must set create_oidc_provider = false.

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_repo             = var.github_repo
  additional_github_repos = var.additional_github_repos

  # Dev creates the OIDC provider; prod reuses it via data source.
  create_oidc_provider = true

  tags = {
    Component = "cicd"
  }
}
