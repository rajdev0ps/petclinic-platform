#!/usr/bin/env bash
# install-eso.sh — Installs External Secrets Operator (ESO) on EKS via Helm (PETPLAT-34).
#
# Prerequisites:
#   - kubectl configured for the target EKS cluster
#   - helm CLI installed
#   - Terraform applied in terraform/environments/{env}/ (ESO IRSA role created)
#
# Usage:
#   ENV=dev bash scripts/install-eso.sh
#   ENV=prod bash scripts/install-eso.sh

set -euo pipefail

ENV="${ENV:-dev}"
ESO_VERSION="${ESO_VERSION:-0.10.7}"
TF_DIR="terraform/environments/${ENV}"

echo "==> Installing External Secrets Operator ${ESO_VERSION} via Helm for environment: ${ENV}"

# 1. Add the ESO Helm repo and install
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version "${ESO_VERSION}" \
  --set installCRDs=true \
  --wait \
  --timeout 120s

echo "==> Waiting for ESO controller to be ready (up to 120s)..."
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=120s

# 2. Get the ESO IRSA role ARN from Terraform output
echo "==> Fetching ESO IRSA role ARN from Terraform..."
ESO_ROLE_ARN=$(terraform -chdir="${TF_DIR}" output -raw eso_role_arn 2>/dev/null || true)

if [[ -z "${ESO_ROLE_ARN}" ]]; then
  echo "ERROR: Could not retrieve eso_role_arn from Terraform output."
  echo "       Run 'terraform apply' in ${TF_DIR} first, then re-run this script."
  exit 1
fi

echo "==> ESO IRSA role ARN: ${ESO_ROLE_ARN}"

# 3. Create and annotate the ESO ServiceAccount for IRSA
kubectl apply -f k8s/base/external-secrets/serviceaccount.yaml
kubectl annotate serviceaccount external-secrets-sa \
  --namespace=external-secrets \
  "eks.amazonaws.com/role-arn=${ESO_ROLE_ARN}" \
  --overwrite

# 4. Apply the ClusterSecretStore
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml

echo "==> Restarting ESO controller to pick up new ServiceAccount annotations..."
kubectl rollout restart deployment/external-secrets -n external-secrets
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=60s

echo ""
echo "==> External Secrets Operator installed successfully."
echo ""
echo "Next steps — apply ExternalSecret manifests:"
echo "  kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml"
echo "  kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml"
echo ""
echo "Verify sync status:"
echo "  kubectl get externalsecrets -n petclinic-${ENV}"
echo "  kubectl get secret rds-credentials -n petclinic-${ENV}"
echo "  kubectl get secret openai-api-key -n petclinic-${ENV}"
echo ""
echo "To add a new secret:"
echo "  1. Create 'petclinic/${ENV}/<name>' in AWS Secrets Manager"
echo "  2. Add an ExternalSecret manifest in k8s/base/external-secrets/"
echo "  3. kubectl apply -f k8s/base/external-secrets/<name>.yaml"
