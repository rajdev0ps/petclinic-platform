#!/usr/bin/env bash
# PETPLAT-29: Install AWS Load Balancer Controller on EKS
# Installs via Helm chart from https://aws.github.io/eks-charts (eks.amazonaws.com/charts).
#
# Usage:
#   ./scripts/install-lb-controller.sh \
#     --cluster-name  petclinic-dev \
#     --region        us-east-1 \
#     --role-arn      arn:aws:iam::ACCOUNT:role/petclinic-dev-lb-controller-role
#
# Prerequisites:
#   - kubectl configured and pointing to the target EKS cluster
#   - helm 3.x installed
#   - AWS CLI configured (aws eks describe-cluster must succeed)
#
# After installation:
#   1. Apply the Ingress: kubectl apply -f k8s/base/ingress/ingress.yaml
#   2. Get the ALB hostname:
#        kubectl get ingress petclinic-ingress -n petclinic-dev \
#          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
#   3. Re-apply Terraform with alb_dns_name and alb_zone_id set to create the Route 53 A record

set -euo pipefail

# Pinned chart version — update after testing a newer version in a non-prod cluster.
# Chart 1.8.3 = AWS Load Balancer Controller v2.8.3 (MED-005 fix)
# Check for new releases: helm search repo eks/aws-load-balancer-controller --versions
LB_CONTROLLER_CHART_VERSION="1.8.3"

# ─── Parse Arguments ──────────────────────────────────────────────────────────

CLUSTER_NAME=""
AWS_REGION="us-east-1"
LB_CONTROLLER_ROLE_ARN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name)  CLUSTER_NAME="$2";            shift 2 ;;
    --region)        AWS_REGION="$2";              shift 2 ;;
    --role-arn)      LB_CONTROLLER_ROLE_ARN="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --cluster-name <name> --region <region> --role-arn <arn>"
      exit 1
      ;;
  esac
done

if [[ -z "$CLUSTER_NAME" || -z "$LB_CONTROLLER_ROLE_ARN" ]]; then
  echo "Error: --cluster-name and --role-arn are required."
  echo "Usage: $0 --cluster-name <name> --region <region> --role-arn <arn>"
  echo ""
  echo "Get the role ARN from Terraform:"
  echo "  terraform -chdir=terraform/environments/dev output -raw dns_lb_controller_role_arn"
  exit 1
fi

# ─── Preflight ────────────────────────────────────────────────────────────────

echo "=== AWS Load Balancer Controller Installation ==="
echo "Cluster:       $CLUSTER_NAME"
echo "Region:        $AWS_REGION"
echo "Role:          $LB_CONTROLLER_ROLE_ARN"
echo "Chart version: $LB_CONTROLLER_CHART_VERSION"
echo ""

# Verify required tools
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }
command -v helm    >/dev/null 2>&1 || { echo "Error: helm not found"; exit 1; }
command -v aws     >/dev/null 2>&1 || { echo "Error: aws CLI not found"; exit 1; }
command -v jq      >/dev/null 2>&1 || { echo "Error: jq not found (required for chart version parsing)"; exit 1; }

# Verify kubectl connectivity
echo "Verifying kubectl connectivity..."
kubectl cluster-info --request-timeout=10s > /dev/null

# Resolve VPC ID from the cluster
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

echo "VPC ID: $VPC_ID"
echo ""

# ─── Step 1: Add Helm Repository ─────────────────────────────────────────────
# Repository: eks.amazonaws.com/charts (hosted at https://aws.github.io/eks-charts)

echo "Step 1: Adding eks Helm repository..."
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || \
  echo "  (repo already exists, skipping add)"
helm repo update eks
echo ""

# ─── Step 2: Install CRDs ────────────────────────────────────────────────────
# The Helm chart bundles CRDs in its crds/ directory and applies them automatically
# on helm install. We also apply them explicitly first for safe upgrades:
# re-applying CRDs is idempotent and ensures they exist before the controller starts.

echo "Step 2: Installing AWS Load Balancer Controller CRDs (chart v${LB_CONTROLLER_CHART_VERSION})..."
CHART_TMP_DIR=$(mktemp -d)
helm pull eks/aws-load-balancer-controller \
  --version "$LB_CONTROLLER_CHART_VERSION" \
  --untar \
  --untardir "$CHART_TMP_DIR"

if [[ -d "$CHART_TMP_DIR/aws-load-balancer-controller/crds" ]]; then
  # Server-side apply without --force-conflicts: conflicts surface as errors (LOW-007 fix)
  kubectl apply -f "$CHART_TMP_DIR/aws-load-balancer-controller/crds/" --server-side
  echo "  CRDs applied successfully."
else
  echo "  No crds/ directory found in chart — CRDs will be applied by helm install."
fi

rm -rf "$CHART_TMP_DIR"
echo ""

# ─── Step 3: Install / Upgrade Controller ────────────────────────────────────

echo "Step 3: Installing AWS Load Balancer Controller via Helm..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --create-namespace \
  --version "${LB_CONTROLLER_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LB_CONTROLLER_ROLE_ARN}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait \
  --timeout 180s

echo ""

# ─── Verify ───────────────────────────────────────────────────────────────────

echo "Verifying deployment..."
kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout 120s

echo ""
echo "Controller pods:"
kubectl get pods -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller

echo ""
echo "IngressClass resources:"
kubectl get ingressclass

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Update k8s/base/ingress/ingress.yaml with the ACM cert ARN:"
echo "       terraform -chdir=terraform/environments/dev output -raw dns_certificate_arn"
echo ""
echo "  2. Apply the Ingress:"
echo "       kubectl apply -f k8s/base/ingress/ingress.yaml"
echo ""
echo "  3. Wait for the ALB to be provisioned (~2 min), then get its hostname:"
echo "       kubectl get ingress petclinic-ingress -n petclinic-dev \\"
echo "         -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "  4. Re-apply Terraform with alb_dns_name and alb_zone_id to wire Route 53 (PETPLAT-31):"
echo "       # In terraform/environments/dev/main.tf, set:"
echo "       #   alb_dns_name = \"<ALB hostname from above>\""
echo "       #   alb_zone_id  = \"Z35SXDOTRQ7X7K\"   # us-east-1"
echo "       terraform -chdir=terraform/environments/dev apply"
