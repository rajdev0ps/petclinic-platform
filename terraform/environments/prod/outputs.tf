output "vpc_id" {
  description = "Prod VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Prod public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.vpc.alb_sg_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "eks_node_role_arn" {
  description = "EKS worker node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "eks_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = module.eks.kubeconfig_command
}

output "eks_ebs_csi_role_arn" {
  description = "EBS CSI driver IRSA role ARN"
  value       = module.eks.ebs_csi_role_arn
}

output "eks_vpc_cni_role_arn" {
  description = "VPC CNI IRSA role ARN"
  value       = module.eks.vpc_cni_role_arn
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value       = module.ecr.repository_arns
}

output "rds_endpoint" {
  description = "Prod RDS instance endpoint hostname"
  value       = module.rds.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Prod RDS instance port"
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "Prod RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Prod Secrets Manager ARN for RDS credentials (used by External Secrets Operator)"
  value       = module.rds.secret_arn
  sensitive   = true
}

output "rds_connection_string" {
  description = "Prod JDBC connection string for Spring datasource (use in K8s ConfigMap)"
  value       = module.rds.connection_string
  sensitive   = true
}

# ─── Secrets Outputs (PETPLAT-33, PETPLAT-37) ────────────────────────────────

output "openai_secret_arn" {
  description = "Prod Secrets Manager ARN for OpenAI API key (referenced by ESO ExternalSecret)"
  value       = module.secrets.openai_secret_arn
  sensitive   = true
}

output "eso_role_arn" {
  description = "Prod ESO IRSA role ARN — annotate the external-secrets-sa ServiceAccount with this value"
  value       = module.secrets.eso_role_arn
}

# ─── GitHub Actions OIDC Outputs (PETPLAT-52) ────────────────────────────────

output "github_actions_role_arn" {
  description = "GitHub Actions IAM role ARN — set as AWS_ROLE_ARN_PROD secret in the app repo"
  value       = module.github_oidc.role_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN (account-scoped, shared with dev)"
  value       = module.github_oidc.oidc_provider_arn
}

# ─── DNS Outputs ─────────────────────────────────────────────────────────────

output "dns_certificate_arn" {
  description = "ACM certificate ARN — paste into ingress annotation"
  value       = module.dns.certificate_arn
}

output "dns_app_fqdn" {
  description = "Prod application FQDN (e.g. petclinic.example.com)"
  value       = module.dns.app_fqdn
}

output "dns_lb_controller_role_arn" {
  description = "LB controller IRSA role ARN — pass to scripts/install-lb-controller.sh"
  value       = module.dns.lb_controller_role_arn
}

# ─── Karpenter Outputs ───────────────────────────────────────────────────────

output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN"
  value       = module.karpenter.karpenter_role_arn
}

output "karpenter_queue_name" {
  description = "Karpenter SQS interruption queue name"
  value       = module.karpenter.karpenter_queue_name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes"
  value       = module.karpenter.karpenter_instance_profile_name
}
