# 📋 Petclinic Infrastructure Report & Operations Playbook

**Date**: August 25, 2026 / August 26, 2026  
**Environment**: `dev` (`us-east-1`)  
**Cluster**: `petclinic-dev`  
**Author**: L7 Principal DevOps Architect  

---

## 🔬 1. Root Cause Analysis & Today's Status

### 🚨 The Core Issue: `KubeletHasInsufficientMemory` on `t4g.small`
During today's operations, `t4g.small` nodes continuously transitioned to `NotReady` / `NodeStatusUnknown`. The exact `kubectl describe node` log revealed:

```text
Conditions:
  Type             Status  Reason                         Message
  MemoryPressure   True    KubeletHasInsufficientMemory   kubelet has insufficient memory available
  Ready            False   KubeletNotReady                node is shutting down
```

#### Memory Math Breakdown on `t4g.small`:
- **Physical Memory**: 2,048 MB (1,887 MB reported by kernel)
- **Kubernetes Allocatable Memory**: 1,366 MB
- **System Overhead (Kernel + Kubelet + containerd + AWS CNI + EBS CSI + Kube-proxy)**: ~1,000 MB
- **Hard Eviction Threshold (`memory.available < 100Mi`)**: 100 MB
- **NET USABLE HEADROOM FOR MICROSERVICES**: **ONLY 266 MB!**

When 2 Java 17 Spring Boot JVM microservices landed on a single `t4g.small` node, total memory usage exceeded physical RAM. Linux OOM killer froze `kubelet`, missing its 40-second heartbeat window, turning the node **`NotReady`**.

---

## 🏛️ 2. Recommended Architecture for Tomorrow

To ensure 100% rock-solid stability with **1 replica per service**:

1. **Instance Type Upgrade**: Upgrade node group to **`t4g.medium`** (2 vCPU, **4.0 GB RAM**, ARM64 Graviton).
   - **Allocatable Memory**: **3,400 MB per node** (vs 1,366 MB on `t4g.small`).
   - **Usable Memory Headroom**: **2,300 MB per node** (8.6x more free memory!).
   - **Node Count**: **3 x `t4g.medium` nodes** comfortably host all 8 microservices with zero memory pressure.
2. **Replica Count**: **1 replica per deployment** (`replicaCount: 1`).
3. **Pod Anti-Affinity**: `topologySpreadConstraints` configured in Helm templates to spread microservices evenly across nodes.

---

## 💣 3. Step-by-Step Teardown Instructions (Tonight)

Run these commands in your shell to cleanly destroy all resources and prevent AWS costs overnight:

### Step 3.1: Clean Kubernetes Resources & Load Balancers
```bash
# Set environment context
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/environments/dev

# 1. Delete Ingress to trigger AWS Load Balancer Controller to delete ALB & Security Groups
kubectl delete ingress petclinic-ingress -n petclinic-dev --ignore-not-found=true

# 2. Delete ArgoCD Applications
kubectl delete -f k8s/argocd/applications/dev/ --ignore-not-found=true

# 3. Delete all microservice workloads in petclinic-dev
kubectl delete ns petclinic-dev --ignore-not-found=true --timeout=60s
```

### Step 3.2: Run Terraform Destroy
```bash
# Execute clean Terraform destruction
terraform destroy -auto-approve -var="openai_api_key=sk-dummy-key-for-destroy"
```

---

## 🚀 4. Step-by-Step Re-Deployment Instructions (Tomorrow)

Follow this exact sequence tomorrow to bring up the entire infrastructure from scratch:

### Step 4.1: Deploy Infrastructure with Terraform (~8 minutes)
```bash
# 1. Navigate to dev environment
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/environments/dev

# 2. Initialize Terraform
terraform init

# 3. Apply Terraform plan with OpenAI key
terraform apply -auto-approve -var="openai_api_key=<YOUR_OPENAI_API_KEY>"

# 4. Update local kubeconfig
aws eks update-kubeconfig --name petclinic-dev --region us-east-1
```

### Step 4.2: Install Core Kubernetes Addons (~2 minutes)
```bash
# 1. Create petclinic-dev namespace
kubectl create namespace petclinic-dev

# 2. Apply Base CRDs and External Secrets Operator (ESO)
kubectl apply -f k8s/base/external-secrets/

# 3. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f k8s/argocd/install/argocd-install.yaml
```

### Step 4.3: Deploy Petclinic Microservices via ArgoCD (~3 minutes)
```bash
# Apply ArgoCD Application manifests for dev environment
kubectl apply -f k8s/argocd/applications/dev/

# Verify node readiness across all nodes
kubectl get nodes -o wide

# Verify all 8 microservices reach 1/1 Running status
kubectl get pods -n petclinic-dev -w
```

### Step 4.4: Verify Public ALB URL Access
```bash
# Get public ALB Load Balancer DNS URL
aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName" --output text

# Test HTTP homepage access
curl.exe -i http://<ALB_DNS_NAME>/
```

---

## 📊 Summary Checklist for Tomorrow

- [ ] Node Group: `t4g.medium` (4GB RAM per node, 3 nodes)
- [ ] Microservice Replicas: 1 replica per deployment (`replicaCount: 1`)
- [ ] Total Microservices: 8 (`admin-server`, `api-gateway`, `config-server`, `customers-service`, `discovery-server`, `genai-service`, `vets-service`, `visits-service`)
- [ ] Public Access: Direct HTTP port 80 via AWS ALB DNS URL
