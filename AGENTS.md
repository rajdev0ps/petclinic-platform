# Petclinic Platform — Antigravity Agent Guidelines

This repository contains ALL infrastructure code for deploying Spring Petclinic Microservices to AWS.
The application repository (`spring-petclinic-microservices`) is READ-ONLY — never modify it.

## Core Rules & Guardrails

1. **No secrets in code** — Use AWS Secrets Manager + External Secrets Operator. Never hardcode passwords, keys, or API tokens.
2. **No public S3 buckets** — Always include `aws_s3_bucket_public_access_block` on all buckets.
3. **No open security groups** — No `0.0.0.0/0` ingress except ALB on ports 80/443. All backend resources are guarded by restrictive security groups.
4. **Encryption everywhere** — Enable encryption at rest for RDS, S3 SSE, EBS, and Secrets Manager.
5. **Least privilege IAM** — Specify exact actions and resource ARNs, never wildcard `*/*`.
6. **No state loss or destruction** — State locking via DynamoDB + S3 versioning. Destructive actions (`terraform destroy`, dangerous deletes) are strictly blocked by hooks.
7. **No .tfvars or secrets committed** — Strictly enforced by `.gitignore` and secret-scanning hooks.

## Directory Layout

```
terraform/environments/{dev,prod}/   # Root modules (one per environment)
terraform/modules/{vpc,eks,ecr,rds,dns,secrets,observability,karpenter}/
helm/petclinic-service/              # Generic Helm chart (shared by all 8 services)
helm-values/                         # Per-service YAML + per-env (dev.yaml, prod.yaml)
k8s/base/                            # Namespaces, external-secrets CRs
k8s/argocd/install/                  # ArgoCD installation manifests
k8s/argocd/applications/{dev,prod}/  # ArgoCD Application CRDs
.github/workflows/                    # CI pipelines (build + push only, ArgoCD handles CD)
scripts/                             # Operational scripts
docs/                                # Architecture docs, runbooks, ADRs
.agents/                             # Antigravity agents, skills, rules, hooks & MCP
```

## Standard Workflows & Commands

```bash
# Terraform workflow (always plan before apply)
terraform fmt -recursive
terraform validate
terraform plan -out plan.out
terraform apply plan.out        # Never apply without a saved plan

# Helm template validation
helm template my-release helm/petclinic-service/ -f helm-values/{service}.yaml -f helm-values/{env}.yaml

# ArgoCD (after install)
kubectl port-forward svc/argocd-server -n argocd 8443:443
argocd app sync {service}-{env}

# Security scanning
checkov -d terraform/modules/{module}
```

## Reference Documentation & Jira Backlog

- Technical Specification: [`docs/technical-spec.md`](docs/technical-spec.md) — Contains exact CIDRs, ports, resource limits, and probe timings.
- Jira Backlog: [`docs/jira-backlog.md`](docs/jira-backlog.md) — Tracks 17 epics covering VPC, EKS, K8s, Helm, and ArgoCD deployment.
- Domain Context: See `.agents/rules/` for specialized rules on Terraform, Kubernetes, Helm, CI/CD pipelines, and Documentation.
