#!/usr/bin/env bash
# setup-env.sh — One-time environment configuration for a new deployment.
#
# This script:
#   Phase 1 (--init):     Collects deployment parameters, generates backend.hcl and
#                         terraform.tfvars for dev + prod, substitutes PLATFORM_REPO_URL
#                         and ECR_REGISTRY_* placeholders in ArgoCD Application CRDs.
#
#   Phase 2 (--post-apply): Reads Terraform outputs (run AFTER terraform apply) and
#                            substitutes RDS_JDBC_URL_* and REPLACE_WITH_ACM_CERT_ARN /
#                            REPLACE_WITH_APP_FQDN in Application CRDs and ingress.yaml.
#
# Usage:
#   ./scripts/setup-env.sh --init          # Run before terraform apply
#   ./scripts/setup-env.sh --post-apply    # Run after terraform apply (dev first)
#
# Prerequisites: AWS CLI configured, git, terraform (phase 2 only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
prompt()  { echo -e "${YELLOW}[INPUT]${NC} $*"; }

# ─── Phase 1: --init ─────────────────────────────────────────────────────────
init() {
  info "=== Petclinic Platform — Environment Setup ==="
  echo ""

  # Auto-detect AWS account ID
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || error "AWS CLI is not configured or credentials are invalid. Run: aws configure"
  info "AWS Account ID detected: ${ACCOUNT_ID}"

  # Auto-detect AWS region
  REGION=$(aws configure get region 2>/dev/null || echo "")
  if [ -z "${REGION}" ]; then
    prompt "AWS region (e.g. us-east-1):"
    read -r REGION
  else
    info "AWS Region detected: ${REGION}"
  fi

  # Auto-detect platform repo URL
  PLATFORM_REPO_URL=$(cd "${REPO_ROOT}" && git remote get-url origin 2>/dev/null || echo "")
  if [ -z "${PLATFORM_REPO_URL}" ]; then
    prompt "Platform repo URL (e.g. https://github.com/myorg/petclinic-platform.git):"
    read -r PLATFORM_REPO_URL
  else
    info "Platform repo URL detected: ${PLATFORM_REPO_URL}"
  fi

  echo ""
  prompt "GitHub app repo (e.g. myorg/spring-petclinic-microservices) [owner/repo format]:"
  read -r GITHUB_APP_REPO

  prompt "GitHub platform repo for additional OIDC trust (e.g. myorg/petclinic-platform) [enter to skip]:"
  read -r GITHUB_PLATFORM_REPO

  prompt "Domain name with existing Route 53 hosted zone (e.g. example.com):"
  read -r DOMAIN_NAME

  prompt "Route 53 hosted zone ID (starts with Z, e.g. Z1D633PJN98FT9):"
  read -r ZONE_ID

  prompt "Your public IP in CIDR notation for EKS API access (e.g. 1.2.3.4/32). Run: curl -s https://checkip.amazonaws.com"
  read -r OPERATOR_CIDR

  prompt "Budget alert email address:"
  read -r BUDGET_EMAIL

  echo ""
  info "Generating backend.hcl files..."
  STATE_BUCKET="petclinic-tfstate-${ACCOUNT_ID}-${REGION}"

  for env in dev prod; do
    cat > "${REPO_ROOT}/terraform/environments/${env}/backend.hcl" <<EOF
bucket         = "${STATE_BUCKET}"
region         = "${REGION}"
dynamodb_table = "petclinic-terraform-locks"
encrypt        = true
EOF
    info "  Written: terraform/environments/${env}/backend.hcl"
  done

  info "Generating terraform.tfvars files..."
  ADDITIONAL_REPOS=""
  if [ -n "${GITHUB_PLATFORM_REPO}" ]; then
    ADDITIONAL_REPOS="additional_github_repos = [\"${GITHUB_PLATFORM_REPO}\"]"
  fi

  for env in dev prod; do
    cat > "${REPO_ROOT}/terraform/environments/${env}/terraform.tfvars" <<EOF
aws_region         = "${REGION}"
domain_name        = "${DOMAIN_NAME}"
zone_id            = "${ZONE_ID}"
github_repo        = "${GITHUB_APP_REPO}"
${ADDITIONAL_REPOS}
budget_alert_email = "${BUDGET_EMAIL}"
eks_public_access_cidrs = ["${OPERATOR_CIDR}"]

# Leave blank until after install-lb-controller.sh + ingress apply:
alb_dns_name = ""
alb_zone_id  = ""

# Sensitive vars — pass via TF_VAR env var, not here:
# export TF_VAR_openai_api_key="sk-..."
EOF
    info "  Written: terraform/environments/${env}/terraform.tfvars"
  done

  info "Substituting PLATFORM_REPO_URL in ArgoCD Application CRDs..."
  ECR_REGISTRY_DEV="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/petclinic-dev"
  ECR_REGISTRY_PROD="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/petclinic-prod"

  for f in "${REPO_ROOT}"/k8s/argocd/applications/dev/*.yaml; do
    sed -i \
      -e "s|PLATFORM_REPO_URL|${PLATFORM_REPO_URL}|g" \
      -e "s|ECR_REGISTRY_DEV|${ECR_REGISTRY_DEV}|g" \
      "$f"
  done

  for f in "${REPO_ROOT}"/k8s/argocd/applications/prod/*.yaml; do
    sed -i \
      -e "s|PLATFORM_REPO_URL|${PLATFORM_REPO_URL}|g" \
      -e "s|ECR_REGISTRY_PROD|${ECR_REGISTRY_PROD}|g" \
      "$f"
  done
  info "  ArgoCD Application CRDs updated."

  echo ""
  info "=== Phase 1 complete. Next steps: ==="
  echo ""
  echo "  1. Bootstrap Terraform state (first time only):"
  echo "       cd terraform/bootstrap"
  echo "       terraform init"
  echo "       terraform apply -var=\"region=${REGION}\""
  echo ""
  echo "  2. Initialize and apply dev environment:"
  echo "       cd terraform/environments/dev"
  echo "       terraform init -backend-config=backend.hcl"
  echo "       export TF_VAR_openai_api_key=\"sk-your-key\""
  echo "       terraform plan -out plan.out"
  echo "       terraform apply plan.out"
  echo ""
  echo "  3. After terraform apply, run:"
  echo "       ./scripts/setup-env.sh --post-apply"
  echo ""
  warn "Commit the updated k8s/argocd/applications/ files to git after this step."
}

# ─── Phase 2: --post-apply ────────────────────────────────────────────────────
post_apply() {
  info "=== Phase 2: Populating Terraform outputs ==="

  DEV_TF="${REPO_ROOT}/terraform/environments/dev"
  PROD_TF="${REPO_ROOT}/terraform/environments/prod"

  # Read dev outputs
  info "Reading dev Terraform outputs..."
  cd "${DEV_TF}"

  RDS_ENDPOINT_DEV=$(terraform output -raw rds_endpoint 2>/dev/null) \
    || error "Could not read rds_endpoint from dev terraform. Ensure dev terraform apply has completed."
  RDS_JDBC_DEV="jdbc:mysql://${RDS_ENDPOINT_DEV}:3306/petclinic"

  ACM_CERT_ARN=$(terraform output -raw dns_certificate_arn 2>/dev/null) \
    || error "Could not read dns_certificate_arn from dev terraform."

  APP_FQDN_DEV=$(terraform output -raw dns_app_fqdn 2>/dev/null) \
    || error "Could not read dns_app_fqdn from dev terraform."

  info "  Dev RDS JDBC URL: ${RDS_JDBC_DEV}"
  info "  ACM cert ARN:     ${ACM_CERT_ARN}"
  info "  App FQDN:         ${APP_FQDN_DEV}"

  # Substitute in dev Application CRDs
  for svc in customers-service visits-service vets-service; do
    f="${REPO_ROOT}/k8s/argocd/applications/dev/${svc}.yaml"
    sed -i "s|RDS_JDBC_URL_DEV|${RDS_JDBC_DEV}|g" "$f"
    info "  Updated: k8s/argocd/applications/dev/${svc}.yaml"
  done

  # Update ingress.yaml
  INGRESS="${REPO_ROOT}/k8s/base/ingress/ingress.yaml"
  sed -i \
    -e "s|REPLACE_WITH_ACM_CERT_ARN|${ACM_CERT_ARN}|g" \
    -e "s|REPLACE_WITH_APP_FQDN|${APP_FQDN_DEV}|g" \
    "${INGRESS}"
  info "  Updated: k8s/base/ingress/ingress.yaml"

  # Try to read prod RDS output (only if prod has been applied)
  if cd "${PROD_TF}" 2>/dev/null && terraform output -raw rds_endpoint &>/dev/null; then
    RDS_ENDPOINT_PROD=$(terraform output -raw rds_endpoint)
    RDS_JDBC_PROD="jdbc:mysql://${RDS_ENDPOINT_PROD}:3306/petclinic"
    for svc in customers-service visits-service vets-service; do
      f="${REPO_ROOT}/k8s/argocd/applications/prod/${svc}.yaml"
      sed -i "s|RDS_JDBC_URL_PROD|${RDS_JDBC_PROD}|g" "$f"
      info "  Updated: k8s/argocd/applications/prod/${svc}.yaml"
    done
  else
    warn "Prod terraform outputs not yet available — RDS_JDBC_URL_PROD left as placeholder."
    warn "Run ./scripts/setup-env.sh --post-apply again after prod terraform apply."
  fi

  echo ""
  info "=== Phase 2 complete. Next steps: ==="
  echo ""
  echo "  1. Commit the updated files:"
  echo "       git add k8s/argocd/applications/ k8s/base/ingress/"
  echo "       git commit -m 'chore: populate terraform outputs into k8s manifests'"
  echo "       git push"
  echo ""
  echo "  2. Apply the ingress manifest:"
  echo "       kubectl apply -f k8s/base/ingress/ingress.yaml"
  echo ""
  echo "  3. Get the ALB hostname and update terraform.tfvars:"
  echo "       kubectl get ingress petclinic-ingress -n petclinic-dev \\"
  echo "         -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  echo "       # Add to terraform/environments/dev/terraform.tfvars:"
  echo "       #   alb_dns_name = \"<output above>\""
  echo "       #   alb_zone_id  = \"Z35SXDOTRQ7X7K\"  # us-east-1 ALB zone ID"
  echo "       cd terraform/environments/dev && terraform apply"
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────
case "${1:-}" in
  --init)       init ;;
  --post-apply) post_apply ;;
  *)
    echo "Usage: $0 --init | --post-apply"
    echo ""
    echo "  --init        Run before terraform apply. Generates backend.hcl, terraform.tfvars,"
    echo "                and substitutes static placeholders in ArgoCD CRDs."
    echo "  --post-apply  Run after terraform apply. Reads RDS endpoint, ACM cert ARN, and"
    echo "                app FQDN from terraform outputs and fills remaining placeholders."
    exit 1
    ;;
esac
