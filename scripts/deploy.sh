#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-api-gateway}"
ENV="${2:-dev}"

REGISTRY="995679261046.dkr.ecr.us-east-1.amazonaws.com/petclinic-${ENV}"
VALUES_FILE="helm-values/${SERVICE}.yaml"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: $VALUES_FILE not found."
  exit 1
fi

# Extract tag without needing yq installed
TAG=$(grep 'tag:' "$VALUES_FILE" | head -1 | sed 's/.*tag:[[:space:]]*"\?\([^"]*\)"\?/\1/')

if [[ -z "$TAG" ]]; then
  echo "Error: Could not parse tag from $VALUES_FILE"
  exit 1
fi

echo "=========================================="
echo "Deploying ${SERVICE}:${TAG} to EKS (${ENV})..."
echo "=========================================="

HELM_ARGS=(
  --namespace "petclinic-${ENV}"
  --set "image.registry=${REGISTRY}"
  --set "image.name=${SERVICE}"
  --set "image.tag=${TAG}"
  -f "$VALUES_FILE"
  -f "helm-values/${ENV}.yaml"
)

# Inject RDS connection string for DB-backed services
if [[ "$SERVICE" =~ ^(customers-service|vets-service|visits-service)$ ]]; then
  RDS_URL="jdbc:mysql://petclinic-dev-mysql.ca98wu4yw5gu.us-east-1.rds.amazonaws.com:3306/petclinic"
  HELM_ARGS+=(--set "configMap.data.SPRING_DATASOURCE_URL=${RDS_URL}")
fi

helm upgrade --install "$SERVICE" helm/petclinic-service/ "${HELM_ARGS[@]}"

echo "Waiting for rollout of $SERVICE..."
kubectl rollout status deployment/"$SERVICE" -n "petclinic-${ENV}" --timeout=120s
echo "Successfully deployed $SERVICE ($TAG) to petclinic-${ENV}!"
