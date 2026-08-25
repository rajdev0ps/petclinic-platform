---
name: smoke-test
description: Run health checks against deployed services
disable-model-invocation: true
argument-hint: "[env]"
---

# /smoke-test [env]

Run smoke tests against deployed services to verify they are healthy.

## Arguments

- `env` — Target environment: `dev` or `prod` (default: `dev`)

## Steps

1. Set the namespace based on environment:
   - `dev` → `petclinic-dev`
   - `prod` → `petclinic-prod`

2. Check if `scripts/smoke-test.sh` exists. If so, run it:
   ```bash
   bash scripts/smoke-test.sh {env}
   ```

3. If the script doesn't exist, run manual health checks:

   a. Check all pods are running:
      ```bash
      kubectl get pods -n petclinic-{env} --no-headers | grep -v Running
      ```
      If any pods are not Running, report them.

   b. For each service, port-forward and check health endpoint:
      ```bash
      kubectl port-forward svc/{service} {local-port}:{service-port} -n petclinic-{env} &
      PF_PID=$!
      sleep 3
      curl -sf http://localhost:{local-port}/actuator/health || echo "FAIL: {service}"
      kill $PF_PID 2>/dev/null
      ```

   c. Service health check ports:
      | Service | Port | Health Endpoint |
      |---------|------|----------------|
      | config-server | 8888 | /actuator/health |
      | discovery-server | 8761 | /actuator/health |
      | api-gateway | 8080 | /actuator/health |
      | customers-service | 8081 | /actuator/health |
      | visits-service | 8082 | /actuator/health |
      | vets-service | 8083 | /actuator/health |
      | genai-service | 8084 | /actuator/health |
      | admin-server | 9090 | /actuator/health |

4. Present results:
   ```
   ## Smoke Test Results: {env}

   | Service | Pod Status | Health Check | Notes |
   |---------|-----------|-------------|-------|
   | config-server | Running | PASS | |
   | discovery-server | Running | PASS | |
   | ... | ... | ... | ... |

   Overall: {N}/8 services healthy
   ```

5. If any service fails, show:
   - Pod status and events
   - Recent logs (last 20 lines)
   - Suggested troubleshooting steps

## Important

- This is a read-only verification — it does not deploy or modify anything
- Port-forwarding is temporary and cleaned up after each check
- For prod, consider using the ingress endpoint instead of port-forwarding
