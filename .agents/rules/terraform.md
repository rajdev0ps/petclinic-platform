---
paths:
  - "terraform/**/*.tf"
  - "terraform/**/*.tfvars"
---

# Terraform Rules

## Module Structure

Every module directory MUST contain:
- `main.tf` — resource definitions
- `variables.tf` — input variables with descriptions and types
- `outputs.tf` — exported values (IDs, ARNs, endpoints)
- `versions.tf` — required_providers block with version constraints

Environment root modules (`terraform/environments/{env}/`) additionally have:
- `backend.tf` — S3 backend configuration
- `terraform.tfvars` — environment-specific variable values (do NOT commit secrets)

## Naming Conventions

- Resource names: `petclinic-{env}-{resource}` (e.g., `petclinic-dev-vpc`)
- Terraform resource identifiers: snake_case (e.g., `aws_vpc.main`, `aws_subnet.private`)
- Variable names: snake_case, descriptive (e.g., `vpc_cidr_block`, `eks_node_instance_type`)
- Output names: snake_case, prefixed by resource type (e.g., `vpc_id`, `eks_cluster_endpoint`)

## Required Tags

Every AWS resource that supports tags MUST include:

```hcl
tags = {
  Project     = "petclinic"
  Environment = var.environment
  ManagedBy   = "terraform"
}
```

## Variable Conventions

- Always include `description` and `type`
- Use `validation` blocks for constrained values (e.g., environment must be "dev" or "prod")
- Use `sensitive = true` for any secret values
- Provide sensible `default` values where appropriate

## Security Requirements

- No inline credentials or hardcoded secrets — use `data "aws_secretsmanager_secret_version"`
- No public S3 buckets — always include `aws_s3_bucket_public_access_block`
- No wildcard IAM — use specific actions and resource ARNs
- Encrypt all storage — RDS, S3, EBS must have encryption enabled
- Security groups as perimeter — all resources in public subnets (cost optimization, no NAT), SGs enforce access control (see ADR-0001)
- Security groups: deny-all default, allow only required ports

## State Management

- Backend: S3 bucket with versioning + DynamoDB for locking
- State key pattern: `petclinic/{env}/terraform.tfstate`
- Never store state locally in production
- Use `terraform_remote_state` data source for cross-module references

## Workflow

1. `terraform fmt -recursive` — format before committing
2. `terraform validate` — syntax check after every edit
3. `terraform plan -out plan.out` — always save the plan
4. Review the plan — check resource counts, changes, deletions
5. `terraform apply plan.out` — apply the saved plan only
