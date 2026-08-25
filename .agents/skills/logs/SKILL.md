---
name: logs
description: View and troubleshoot service logs and pod status
disable-model-invocation: true
argument-hint: "[service] [env]"
---

# /logs [service] [env]

View logs and debug information for a service in the specified environment.

## Arguments

- `service` — Service name (e.g., `config-server`, `api-gateway`, `customers-service`)
- `env` — Target environment: `dev` or `prod` (default: `dev`)

## Steps

1. Set the namespace based on environment:
   - `dev` → `petclinic-dev`
   - `prod` → `petclinic-prod`

2. Show pod status for the service:
   ```bash
   kubectl get pods -l app.kubernetes.io/name={service} -n petclinic-{env} -o wide
   ```

3. Show recent events for the pod:
   ```bash
   kubectl describe pod -l app.kubernetes.io/name={service} -n petclinic-{env} | tail -30
   ```

4. Show logs (last 100 lines):
   ```bash
   kubectl logs -l app.kubernetes.io/name={service} -n petclinic-{env} --tail=100
   ```

5. If the pod is in CrashLoopBackOff, show previous container logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name={service} -n petclinic-{env} --previous --tail=50
   ```

6. Show resource usage if metrics-server is available:
   ```bash
   kubectl top pod -l app.kubernetes.io/name={service} -n petclinic-{env} 2>/dev/null || echo "Metrics server not available"
   ```

7. Present a summary:
   ```
   ## Logs: {service} ({env})

   Pod Status: {Running/CrashLoopBackOff/Pending/etc.}
   Restarts: {count}
   Uptime: {age}

   ### Recent Events
   {key events}

   ### Log Highlights
   {errors/warnings from logs}

   ### Suggested Actions
   {troubleshooting suggestions based on findings}
   ```

## Important

- This is read-only — it does not restart or modify anything
- For prod, be careful with log volume — always use --tail to limit output
- If service name is omitted, show status of ALL pods in the namespace
