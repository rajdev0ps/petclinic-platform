variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "domain_name" {
  description = "Root domain name matching the Route 53 hosted zone (e.g. example.com). Must be a registered domain with a public hosted zone in the target AWS account."
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

# ─── EKS OIDC (for LB controller IRSA) ───────────────────────────────────────

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS cluster — used to scope the LB controller IRSA trust"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without 'https://' prefix — used in the IRSA StringEquals condition"
  type        = string
}

# ─── ALB (filled in after Ingress is applied) ────────────────────────────────
# Leave empty on the first apply. After running install-lb-controller.sh and
# applying k8s/base/ingress/ingress.yaml, get the ALB details with:
#   kubectl get ingress -n petclinic-{env} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
# Then re-apply Terraform with these values populated (PETPLAT-31).

variable "alb_dns_name" {
  description = "ALB DNS hostname created by the LB controller (populate after Ingress is applied)"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB for Route 53 alias target. us-east-1=Z35SXDOTRQ7X7K, eu-central-1=Z215JYRZR1TBD5. See: https://docs.aws.amazon.com/general/latest/gr/elb.html"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge with module defaults"
  type        = map(string)
  default     = {}
}
