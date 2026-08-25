---
name: deploy-prod
description: Deploy services to the prod EKS namespace via ArgoCD (manual sync) with safety checks
disable-model-invocation: true
argument-hint: "[service|all]"
---

# /deploy-prod [service|all]

Deploy services to the petclinic-prod namespace with extra safety checks.

## Arguments

- `service` — Specific service to deploy (e.g., `config-server`, `api-gateway`) or `all`
- Default: `all`

## Steps

1. **Pre-deployment checks:**
   - Verify kubectl context is the prod cluster:
     ```bash
     kubectl config current-context
     ```
   - Check if ArgoCD is installed:
     ```bash
     kubectl get namespace argocd 2>/dev/null
     ```

2. **Explicit confirmation required:**
   Ask the user: "You are deploying to PRODUCTION (petclinic-prod). This will affect live services. Confirm?"
   Do NOT proceed without explicit "yes" from the user.

3. **If ArgoCD is installed (standard path):**

   - Show what ArgoCD will sync (diff):
     ```bash
     argocd app diff {service}-prod || true
     ```
   - **all**: Sync services one at a time (sequential, not bulk):
     ```bash
     # Startup order: config-server first, then discovery-server, then rest
     argocd app sync config-server-prod && argocd app wait config-server-prod --timeout 180
     argocd app sync discovery-server-prod && argocd app wait discovery-server-prod --timeout 180
     # Then remaining services one at a time
     for svc in api-gateway customers-service visits-service vets-service genai-service admin-server; do
       argocd app sync ${svc}-prod && argocd app wait ${svc}-prod --timeout 180
     done
     ```
   - **specific service**: Sync that service:
     ```bash
     argocd app sync {service}-prod
     argocd app wait {service}-prod --timeout 180
     ```
   - If a service fails, STOP and report — do not continue to the next service.

4. **If ArgoCD is NOT installed (bootstrap path):**

   - Apply namespace (idempotent):
     ```bash
     kubectl apply -f k8s/base/namespaces.yaml
     ```
   - **Sequential deployment** (one service at a time, verify each):
     ```bash
     helm upgrade --install {service} helm/petclinic-service/ \
       -f helm-values/{service}.yaml \
       -f helm-values/prod.yaml \
       -n petclinic-prod --create-namespace
     kubectl rollout status deployment/{service} -n petclinic-prod --timeout=180s
     ```
   - If a service fails, STOP and report — do not continue to the next service.

5. **Startup order** (when deploying all):
   1. config-server → wait for ready
   2. discovery-server → wait for ready
   3. All remaining services (one at a time)

6. **Post-deployment verification:**
   ```bash
   kubectl get pods -n petclinic-prod -o wide
   kubectl get svc -n petclinic-prod
   ```

7. Show a deployment summary:
   - Services deployed
   - Pod status (Running/Pending/CrashLoopBackOff)
   - Any issues encountered

## Important

- PRODUCTION deployment — extra caution required
- ArgoCD prod apps require **manual sync** (no auto-sync)
- Always show diff before syncing
- Always get explicit user confirmation
- Deploy sequentially, verify each service before the next
- If any service fails, STOP immediately — do not cascade failures
- Suggest running `/smoke-test prod` after successful deployment
