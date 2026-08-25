#!/usr/bin/env bash
# Validates all 8 petclinic Helm releases.
# Steps per service per env: helm lint, helm template, kubectl apply --dry-run=client.
set -euo pipefail

CHART="helm/petclinic-service"
VALUES_DIR="helm-values"
ENVS=("dev" "prod")
SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)

declare -A NAMESPACE_MAP=([dev]="petclinic-dev" [prod]="petclinic-prod")

PASS=0
FAIL=0

log()  { echo "[INFO]  $*"; }
ok()   { echo "[PASS]  $*"; ((PASS++)) || true; }
fail() { echo "[FAIL]  $*"; ((FAIL++)) || true; }

# ── 1. helm lint (chart-level, once) ────────────────────────────────────────
log "Running helm lint on chart..."
if helm lint "$CHART" --quiet; then
  ok "helm lint $CHART"
else
  fail "helm lint $CHART"
fi

# ── 2. Per-service per-env: lint, template, dry-run ─────────────────────────
for svc in "${SERVICES[@]}"; do
  for env in "${ENVS[@]}"; do
    ns="${NAMESPACE_MAP[$env]}"
    label="$svc / $env"

    # helm lint with merged values
    if helm lint "$CHART" \
        -f "$VALUES_DIR/$svc.yaml" \
        -f "$VALUES_DIR/$env.yaml" \
        --set "image.tag=abc1234" \
        --namespace "$ns" \
        --quiet 2>&1; then
      ok "helm lint       $label"
    else
      fail "helm lint       $label"
    fi

    # helm template → kubectl dry-run
    rendered=$(helm template "$svc" "$CHART" \
      -f "$VALUES_DIR/$svc.yaml" \
      -f "$VALUES_DIR/$env.yaml" \
      --set "image.tag=abc1234" \
      --namespace "$ns" 2>&1)

    if [ $? -ne 0 ]; then
      fail "helm template   $label"
      echo "$rendered"
      continue
    fi
    ok "helm template   $label"

    if echo "$rendered" | kubectl apply --dry-run=client -f - --namespace "$ns" 2>&1; then
      ok "kubectl dry-run $label"
    else
      fail "kubectl dry-run $label"
    fi
  done
done

# ── 3. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════"

[ "$FAIL" -eq 0 ]
