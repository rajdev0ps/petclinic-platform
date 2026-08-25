output "zone_id" {
  description = "Route 53 hosted zone ID (in external account 025760030746 for POC)"
  value       = var.zone_id
}

output "certificate_arn" {
  description = "Validated ACM certificate ARN — use in alb.ingress.kubernetes.io/certificate-arn annotation"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "certificate_domain" {
  description = "Wildcard domain covered by the ACM certificate"
  value       = aws_acm_certificate.main.domain_name
}

output "app_fqdn" {
  description = "Fully qualified domain name for this environment's app (e.g. petclinic-dev.mymilliq1.com)"
  value       = local.app_fqdn
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller — pass to scripts/install-lb-controller.sh"
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_policy_arn" {
  description = "IAM policy ARN attached to the LB controller role"
  value       = aws_iam_policy.lb_controller.arn
}
