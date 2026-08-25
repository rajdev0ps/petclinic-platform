variable "aws_region" {
  description = "AWS region for all resources. Must match the region used in bootstrap and backend.hcl."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service. Pass via TF_VAR_openai_api_key env var — never hardcode or commit."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "Email address for AWS Budget cost alert notifications (50%/80%/100% of $100/month)"
  type        = string
}

variable "domain_name" {
  description = "Root domain name with an existing Route 53 public hosted zone (e.g. example.com). Purchase the domain manually and create the hosted zone before running terraform."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone ID for domain_name. Retrieve with: aws route53 list-hosted-zones-by-name --dns-name <domain>"
  type        = string
  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,32}$", var.zone_id))
    error_message = "zone_id must start with 'Z' followed by uppercase letters and digits (e.g. Z1D633PJN98FT9)."
  }
}

variable "alb_dns_name" {
  description = "ALB DNS hostname created by the LB controller. Leave empty on first apply. After applying k8s/base/ingress/ingress.yaml, get the value with: kubectl get ingress petclinic-ingress -n petclinic-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB for Route 53 alias record. us-east-1=Z35SXDOTRQ7X7K, eu-west-1=Z32O12XQLNTSW2, eu-central-1=Z215JYRZR1TBD5. See: https://docs.aws.amazon.com/general/latest/gr/elb.html"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository for the Spring Petclinic Microservices app in 'owner/repo' format (e.g. myorg/spring-petclinic-microservices). Used in the OIDC trust policy for GitHub Actions."
  type        = string
}

variable "additional_github_repos" {
  description = "Additional GitHub repositories allowed to assume the ECR push role (e.g. the platform repo for manual workflow_dispatch triggers). Format: [\"owner/repo\"]"
  type        = list(string)
  default     = []
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API server. Restrict to operator/VPN IPs. Get your IP: curl -s https://checkip.amazonaws.com then append /32."
  type        = list(string)
}
