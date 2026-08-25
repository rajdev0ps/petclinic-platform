module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  # VPC Network Design — prod CIDR non-overlapping with dev (10.0.0.0/16) for future VPC peering
  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["${var.aws_region}a", "${var.aws_region}b"]

  tags = {
    Component = "networking"
  }
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  cluster_version = "1.35"
  subnet_ids      = module.vpc.public_subnet_ids
  cluster_sg_id   = module.vpc.eks_cluster_sg_id
  node_sg_id      = module.vpc.eks_node_sg_id

  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
  node_disk_size      = 20

  public_access_cidrs = var.eks_public_access_cidrs

  tags = {
    Component = "compute"
  }
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  # IMMUTABLE tags in prod — prevents overwriting deployed images
  image_tag_mutability = "IMMUTABLE"

  tags = {
    Component = "registry"
  }
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 20
  multi_az              = false

  # Prod: longer retention, keep final snapshot, enable deletion protection
  backup_retention_period = 30
  skip_final_snapshot     = false
  deletion_protection     = true

  tags = {
    Component = "database"
  }
}

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

# ─── DNS & Ingress ────────────────────────────────────────────────────────────
# Prod uses subdomain: petclinic.var.domain_name (e.g. petclinic.example.com)
# Dev uses: petclinic-dev.var.domain_name
# This is controlled by the DNS module's app_subdomain local.

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

# ─── GitHub Actions OIDC Federation ──────────────────────────────────────────
# The OIDC provider is account-scoped and created by the dev environment.
# Prod looks it up via data source and reuses it.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_repo             = var.github_repo
  additional_github_repos = var.additional_github_repos

  # Dev creates the OIDC provider; prod reuses it.
  create_oidc_provider = false
  oidc_provider_arn    = data.aws_iam_openid_connect_provider.github.arn

  tags = {
    Component = "cicd"
  }
}
