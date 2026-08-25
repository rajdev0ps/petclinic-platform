# Rollback Runbook

**Scope:** Spring Petclinic Microservices on EKS  
**CD tool:** ArgoCD (GitOps — the Git commit is the source of truth)  
**Applies to:** All 8 services in `petclinic-dev` and `petclinic-prod`

---

## When to Roll Back

Roll back when a deployment causes any of the following:
- Service health checks failing (readiness/liveness probes)
- Error rate spike visible in Grafana or `kubectl logs`
- ArgoCD shows a service `Degraded` after sync
- Business-level regression confirmed by testing

---

## Method 1 — GitOps Rollback (Preferred)

Revert the image tag commit in Git. ArgoCD detects the revert and deploys the previous image.

### Step 1 — Find the last good commit

```bash
git log --oneline helm-values/
# Example output:
# a1b2c3d ci: update image tags to abc1234 (customers-service visits-service)
# e4f5g6h ci: update image tags to def5678 (customers-service)   ← last known good
```

### Step 2 — Revert the bad commit

```bash
# Revert the specific bad commit (creates a new commit — safe for shared history)
git revert a1b2c3d --no-edit
git push origin main
```

### Step 3 — ArgoCD syncs automatically (dev) or manually (prod)

**Dev:** ArgoCD auto-sync picks up the revert within ~30 seconds.

**Prod:** Log into ArgoCD UI and click **Sync** for the affected service(s):
```bash
# Or via CLI:
argocd app sync {service}-prod
```

### Step 4 — Verify

```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}
kubectl rollout status deployment/{service} -n petclinic-{env}
```

---

## Method 2 — ArgoCD History Rollback

Use ArgoCD's built-in rollback to a previous sync revision — no Git change required. Useful when you need the fastest possible recovery without touching Git.

### Via ArgoCD UI

1. Open ArgoCD UI → select the affected application (e.g., `customers-service-dev`)
2. Click **History and Rollback**
3. Select the last successful sync entry
4. Click **Rollback** → confirm

> **Note:** ArgoCD will mark the app as `OutOfSync` after rollback because the live state differs from the Git HEAD. Follow up with a GitOps rollback (Method 1) to realign Git.

### Via ArgoCD CLI

```bash
# List sync history
argocd app history customers-service-dev

# Roll back to a specific revision ID
argocd app rollback customers-service-dev {revision-id}
```

---

## Method 3 — Emergency: kubectl rollout undo

Use only when ArgoCD is unavailable or the situation requires immediate action before the Git/ArgoCD path is ready.

```bash
kubectl rollout undo deployment/{service} -n petclinic-{env}

# Verify the previous ReplicaSet is now active
kubectl rollout status deployment/{service} -n petclinic-{env}

# Check which image is now running
kubectl get deployment {service} -n petclinic-{env} \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> **Warning:** `kubectl rollout undo` puts the live cluster out of sync with Git. ArgoCD will detect drift and may re-apply the bad version on the next sync. Immediately follow up with a GitOps rollback (Method 1) and then re-sync ArgoCD to restore consistency.

---

## Rollback Decision Tree

```
Deployment failed
       │
       ▼
Is ArgoCD available?
  ├── Yes → Is speed critical?
  │           ├── No  → Method 1 (GitOps revert — cleanest)
  │           └── Yes → Method 2 (ArgoCD history rollback)
  │                     then follow up with Method 1
  └── No  → Method 3 (kubectl rollout undo)
            then follow up with Method 1 once stable
```

---

## Per-Environment Notes

| Environment | ArgoCD sync | After rollback |
|-------------|-------------|----------------|
| `petclinic-dev` | Auto-sync (immediate) | Verify pods are Running; ArgoCD auto-corrects |
| `petclinic-prod` | Manual sync required | Must click Sync in ArgoCD UI after Git revert |

---

## Verifying a Successful Rollback

```bash
# 1. Confirm pods are running the expected image
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service} -o wide

# 2. Check the image tag on the running deployment
kubectl get deployment {service} -n petclinic-{env} \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 3. Confirm ArgoCD shows Healthy + Synced
argocd app get {service}-{env}

# 4. Watch readiness (should reach 1/1 within the startup probe window)
kubectl rollout status deployment/{service} -n petclinic-{env} --timeout=120s
```

---

## Related

- CI/CD pipeline: `.github/workflows/update-image-tags.yml`
- ArgoCD Applications: `k8s/argocd/applications/{dev,prod}/`
- Technical spec: `docs/technical-spec.md` — CI/CD Pipeline section
