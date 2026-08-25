---
name: rollback
description: Roll back a failed deployment to the previous revision
disable-model-invocation: true
argument-hint: "[service] [env]"
---

# /rollback [service] [env]

Roll back a failed deployment to its previous working revision.

## Arguments

- `service` — Service to roll back (e.g., `api-gateway`, `customers-service`) or `all`
- `env` — Target environment: `dev` or `prod` (default: `dev`)

## Steps

1. Set the namespace:
   - `dev` → `petclinic-dev`
   - `prod` → `petclinic-prod`

2. Show current rollout status and history:
   ```bash
   kubectl rollout status deployment/{service} -n petclinic-{env}
   kubectl rollout history deployment/{service} -n petclinic-{env}
   ```

3. Show what changed in the current revision vs previous:
   ```bash
   kubectl rollout history deployment/{service} -n petclinic-{env} --revision={current}
   kubectl rollout history deployment/{service} -n petclinic-{env} --revision={previous}
   ```

4. **For prod: require explicit confirmation.**
   Show: "Rolling back {service} in PRODUCTION to revision {N}. This will change the running image. Confirm?"

5. Execute the rollback:
   ```bash
   kubectl rollout undo deployment/{service} -n petclinic-{env}
   ```

6. Monitor rollout:
   ```bash
   kubectl rollout status deployment/{service} -n petclinic-{env} --timeout=120s
   ```

7. Verify the rollback:
   ```bash
   kubectl get pods -l app.kubernetes.io/name={service} -n petclinic-{env}
   ```

8. If rolling back `all`:
   - Roll back in reverse order (application services first, then discovery, then config)
   - Verify each service before proceeding to the next
   - If any rollback fails, stop and report

9. Show summary:
   ```
   ## Rollback: {service} ({env})

   Previous revision: {N} (image: {old-image})
   Rolled back to: {N-1} (image: {previous-image})
   Status: {success/failed}
   Pod status: {Running/etc}
   ```

## Important

- Always get explicit confirmation for prod rollbacks
- When rolling back `all`, go in reverse deployment order
- If rollback fails, do NOT retry — investigate first
- Suggest running `/smoke-test {env}` after rollback to verify health
