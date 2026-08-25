#!/usr/bin/env bash
set -euo pipefail

#
# build-push.sh — Build ARM64 Docker images and push to ECR
#
# Builds JARs with Maven, then uses docker buildx to produce linux/arm64
# images for Graviton t4g EKS nodes.  Does NOT use Maven's buildDocker profile.
#
# Usage:
#   ./scripts/build-push.sh --env dev --tag v1.0.0
#   ./scripts/build-push.sh --env dev --tag $(git -C <app-repo> rev-parse --short HEAD)
#   ./scripts/build-push.sh --env dev --tag v1.0.0 --service api-gateway
#
# Prerequisites:
#   - AWS CLI configured with ECR push permissions
#   - Docker with buildx and QEMU (for cross-platform ARM64 builds on x86)
#   - Java 17 + Maven wrapper in the app repo
#

# ─── Defaults ─────────────────────────────────────────────────────────────────

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
APP_REPO_DIR="${APP_REPO_DIR:-$(dirname "$(dirname "$(realpath "$0")")")/../spring-petclinic-microservices}"
ENV=""
TAG=""
SPECIFIC_SERVICE=""
SKIP_BUILD=false

# ─── Service metadata ─────────────────────────────────────────────────────────
# Maps ECR service name → Maven module name → exposed port
# Ports are authoritative (pom.xml values are often wrong — see technical-spec.md)

declare -A MAVEN_MODULE=(
  [config-server]="spring-petclinic-config-server"
  [discovery-server]="spring-petclinic-discovery-server"
  [api-gateway]="spring-petclinic-api-gateway"
  [customers-service]="spring-petclinic-customers-service"
  [visits-service]="spring-petclinic-visits-service"
  [vets-service]="spring-petclinic-vets-service"
  [genai-service]="spring-petclinic-genai-service"
  [admin-server]="spring-petclinic-admin-server"
)

declare -A SERVICE_PORT=(
  [config-server]=8888
  [discovery-server]=8761
  [api-gateway]=8080
  [customers-service]=8081
  [visits-service]=8082
  [vets-service]=8083
  [genai-service]=8084
  [admin-server]=9090
)

ALL_SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)

# ─── Argument parsing ─────────────────────────────────────────────────────────

usage() {
  echo "Usage: $0 --env <dev|prod> --tag <tag> [--service <name>] [--skip-build] [--region <region>]"
  echo ""
  echo "Options:"
  echo "  --env       Environment: dev or prod (required)"
  echo "  --tag       Image tag, e.g. v1.0.0 or git SHA (required)"
  echo "  --service   Build and push a single service only (optional)"
  echo "  --skip-build  Skip Maven build, use existing JARs (optional)"
  echo "  --region    AWS region (default: us-east-1)"
  echo ""
  echo "Examples:"
  echo "  $0 --env dev --tag v1.0.0"
  echo "  $0 --env dev --tag abc1234 --service api-gateway"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)     ENV="$2";             shift 2 ;;
    --tag)     TAG="$2";             shift 2 ;;
    --service) SPECIFIC_SERVICE="$2"; shift 2 ;;
    --region)  REGION="$2";          shift 2 ;;
    --skip-build) SKIP_BUILD=true;   shift   ;;
    --app-repo)   APP_REPO_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$ENV" || -z "$TAG" ]] && { echo "Error: --env and --tag are required."; usage; }
[[ "$ENV" != "dev" && "$ENV" != "prod" ]] && { echo "Error: --env must be 'dev' or 'prod'"; exit 1; }

# Resolve app repo path
APP_REPO_DIR="$(realpath "$APP_REPO_DIR")"
if [[ ! -f "${APP_REPO_DIR}/mvnw" ]]; then
  echo "Error: App repo not found at ${APP_REPO_DIR}"
  echo "Set APP_REPO_DIR env var or use --app-repo <path>"
  exit 1
fi

# ─── Setup ────────────────────────────────────────────────────────────────────

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
NAMESPACE="petclinic-${ENV}"

SERVICES_TO_BUILD=("${ALL_SERVICES[@]}")
if [[ -n "$SPECIFIC_SERVICE" ]]; then
  if [[ -z "${MAVEN_MODULE[$SPECIFIC_SERVICE]+_}" ]]; then
    echo "Error: Unknown service '${SPECIFIC_SERVICE}'"
    echo "Valid services: ${ALL_SERVICES[*]}"
    exit 1
  fi
  SERVICES_TO_BUILD=("$SPECIFIC_SERVICE")
fi

echo "============================================================"
echo "  Petclinic Build & Push"
echo "  Environment : ${ENV}"
echo "  Tag         : ${TAG}"
echo "  Registry    : ${REGISTRY}/${NAMESPACE}"
echo "  Services    : ${SERVICES_TO_BUILD[*]}"
echo "  App repo    : ${APP_REPO_DIR}"
echo "============================================================"
echo ""

# ─── Step 1: Maven build (compile + package JARs, skip tests) ─────────────────

if [[ "$SKIP_BUILD" == "false" ]]; then
  echo "[1/3] Building JARs with Maven (skipping tests)..."
  cd "${APP_REPO_DIR}"
  ./mvnw clean package -DskipTests --no-transfer-progress
  echo "      Maven build complete."
  echo ""
else
  echo "[1/3] Skipping Maven build (--skip-build set)."
  echo ""
fi

# ─── Step 2: Ensure buildx builder with QEMU for linux/arm64 ─────────────────

echo "[2/3] Setting up Docker buildx for linux/arm64..."

# Create a dedicated builder if it doesn't exist
if ! docker buildx inspect petclinic-arm64 &>/dev/null; then
  docker buildx create --name petclinic-arm64 --driver docker-container --use
else
  docker buildx use petclinic-arm64
fi

# Register QEMU for cross-platform builds on x86 hosts
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes &>/dev/null || true

echo "      Buildx ready."
echo ""

# ─── Step 3: ECR login ────────────────────────────────────────────────────────

echo "[3/3] Authenticating to ECR..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"
echo "      ECR login successful."
echo ""

# ─── Step 4: Build and push each service ──────────────────────────────────────

DOCKERFILE="${APP_REPO_DIR}/docker/Dockerfile"
FAILED_SERVICES=()

for SERVICE in "${SERVICES_TO_BUILD[@]}"; do
  MODULE="${MAVEN_MODULE[$SERVICE]}"
  PORT="${SERVICE_PORT[$SERVICE]}"
  IMAGE_URI="${REGISTRY}/${NAMESPACE}/${SERVICE}:${TAG}"

  # Find the JAR — Maven places it in target/ with version suffix
  JAR_PATH=$(find "${APP_REPO_DIR}/${MODULE}/target" -maxdepth 1 -name "${MODULE}-*.jar" \
    ! -name "*-sources.jar" ! -name "*-javadoc.jar" 2>/dev/null | head -1)

  if [[ -z "$JAR_PATH" ]]; then
    echo "  [SKIP] ${SERVICE}: JAR not found in ${MODULE}/target/ — run Maven build first"
    FAILED_SERVICES+=("$SERVICE")
    continue
  fi

  JAR_NAME=$(basename "$JAR_PATH" .jar)

  echo "  Building ${SERVICE} (port ${PORT}) → ${IMAGE_URI}"
  echo "    JAR: ${JAR_PATH}"

  docker buildx build \
    --platform linux/arm64 \
    --build-arg ARTIFACT_NAME="${JAR_NAME}" \
    --build-arg EXPOSED_PORT="${PORT}" \
    --file "${DOCKERFILE}" \
    --tag "${IMAGE_URI}" \
    --provenance=false \
    --push \
    "${APP_REPO_DIR}/${MODULE}/target/"

  echo "    Pushed: ${IMAGE_URI}"
  echo ""
done

# ─── Summary ──────────────────────────────────────────────────────────────────

echo "============================================================"
if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
  echo "  All images built and pushed successfully."
  echo ""
  echo "  Pull example:"
  echo "    docker pull ${REGISTRY}/${NAMESPACE}/api-gateway:${TAG}"
else
  echo "  WARNING: The following services failed:"
  for s in "${FAILED_SERVICES[@]}"; do echo "    - $s"; done
  echo ""
  echo "  Run Maven build first: cd ${APP_REPO_DIR} && ./mvnw clean package -DskipTests"
  exit 1
fi
echo "============================================================"
