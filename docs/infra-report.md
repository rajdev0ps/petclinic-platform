# 📋 Petclinic End-to-End Infrastructure & Operations Playbook

**Date**: August 26, 2026  
**Environment**: `dev` (`us-east-1`)  
**Cluster**: `petclinic-dev` (AWS EKS 1.35)  
**Author**: L7 Principal DevOps Architect  

---

## 📑 Executive Overview

This playbook documents the **complete operational lifecycle** for tearing down all AWS resources (to prevent overnight charges) and provisioning the entire Petclinic Microservices Platform from scratch.

### 🏛️ Architecture Specifications:
- **Compute**: AWS EKS 1.35 with 5 x `t4g.small` Graviton ARM64 nodes (100% Free Tier eligible).
- **Database**: AWS RDS MySQL 8.0 (`db.t4g.micro`, single-AZ).
- **Security & Secrets**: AWS Secrets Manager + External Secrets Operator (ESO) + OIDC IRSA.
- **Networking & Ingress**: AWS Load Balancer Controller (ALB IP target mode, direct Pod IP routing on port 8080).
- **Container Registry**: AWS ECR (`petclinic-dev/<service>`).
- **CI/CD**: GitHub Actions OIDC federation + Trivy security scanning + manual/script deployment.

---

## 💣 PHASE 1: TEAR DOWN & CLEANUP (Overnight Destruction)

Follow these steps to destroy all AWS resources and avoid overnight cloud costs.

### Step 1.1: Delete K8s Ingress, Helm Releases, and Namespaces
Deleting the Ingress first allows the AWS Load Balancer Controller to cleanly deregister Target Groups and delete the AWS ALB in EC2 before destroying cluster nodes.

```bash
# 1. Navigate to petclinic-antigravity root
cd /s/Interview-prep/project-repos/petclinic-antigratvity

# 2. Delete Ingress resource to delete AWS ALB
kubectl delete ingress petclinic-ingress -n petclinic-dev --ignore-not-found=true

# 3. Uninstall all Helm releases in petclinic-dev
helm uninstall api-gateway customers-service vets-service visits-service genai-service discovery-server config-server admin-server -n petclinic-dev || true

# 4. Delete petclinic-dev namespace
kubectl delete namespace petclinic-dev --ignore-not-found=true --timeout=60s
```

### Step 1.2: Destroy Dev Infrastructure via Terraform
```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/environments/dev

# Run terraform destroy
terraform destroy -auto-approve -var="openai_api_key=sk-dummy-key-for-destroy"
```

### Step 1.3: Destroy S3 State Bucket & DynamoDB Lock Table (Optional - Full Wipe)
```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/bootstrap

# Empty S3 bucket before destroy (if versioning enabled)
aws s3 rm s3://petclinic-terraform-state-995679261046 --recursive || true

# Destroy bootstrap resources
terraform destroy -auto-approve
```

### Step 1.4: Tear Down Verification
Verify that zero billable resources remain in your AWS account:

```bash
# Verify EKS cluster is gone
aws eks list-clusters --region us-east-1

# Verify RDS databases are gone
aws rds describe-db-instances --region us-east-1 --query "DBInstances[*].DBInstanceIdentifier"

# Verify ALBs are gone
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[*].LoadBalancerName"

# Verify EC2 instances are terminated
aws ec2 describe-instances --region us-east-1 --filters "Name=instance-state-name,Values=running,pending" --query "Reservations[*].Instances[*].InstanceId"
```

---

## 🚀 PHASE 2: BRING INFRASTRUCTURE UP FROM SCRATCH

Follow these steps when starting fresh in the morning to recreate all infrastructure.

### Step 2.1: Provision Bootstrap Backend (S3 + DynamoDB)
```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/bootstrap

terraform init
terraform apply -auto-approve
```

### Step 2.2: Provision Core Infrastructure (VPC, EKS, RDS, ECR, OIDC)
```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity/terraform/environments/dev

# 1. Initialize Terraform modules
terraform init -upgrade

# 2. Apply infrastructure plan
terraform apply -auto-approve -var="openai_api_key=<YOUR_OPENAI_API_KEY>"

# 3. Update local kubeconfig to connect to new EKS cluster
aws eks update-kubeconfig --name petclinic-dev --region us-east-1
```

### Step 2.3: Infrastructure Validation
```bash
# Verify all 5 nodes are Ready
kubectl get nodes -o wide

# Verify RDS MySQL status is 'available'
aws rds describe-db-instances --region us-east-1 --query "DBInstances[*].[DBInstanceIdentifier, DBInstanceStatus, Endpoint.Address]" --output table
```

---

## 🔐 PHASE 3: PLATFORM ADD-ONS & SECRETS (ESO, LB Controller, Ingress)

Install core operational controllers and ingress routing onto the cluster.

### Step 3.1: Install External Secrets Operator (ESO) + IRSA
```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity

# Run automated ESO installer
./scripts/install-eso.sh
```

### Step 3.2: Install AWS Load Balancer Controller + IRSA
```bash
# Run automated Load Balancer Controller installer
./scripts/install-lb-controller.sh
```

### Step 3.3: Apply K8s Base Namespaces, Secrets & Ingress
```bash
# Create namespaces and ExternalSecrets CRDs
kubectl apply -f k8s/base/namespaces/
kubectl apply -f k8s/base/external-secrets/

# Apply ingress resource
kubectl apply -f k8s/base/ingress/ingress.yaml
```

### Step 3.4: Add-ons Validation
```bash
# Verify External Secrets Operator pod is 1/1 Running
kubectl get pods -n external-secrets

# Verify AWS Load Balancer Controller pods are 2/2 Running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify Ingress and obtain public ALB DNS URL
kubectl get ingress -n petclinic-dev
```

---

## 📦 PHASE 4: APPLICATION DEPLOYMENT (Deploy All 8 Microservices)

Deploy all 8 Spring Petclinic microservices using the operational deploy script.

### Step 4.1: Deploy All 8 Microservices via Deploy Script
Run the helper script for all microservices in dependency order:

```bash
cd /s/Interview-prep/project-repos/petclinic-antigratvity

# 1. Infrastructure Core Services
./scripts/deploy.sh config-server
./scripts/deploy.sh discovery-server

# 2. Database-backed Business Services
./scripts/deploy.sh customers-service
./scripts/deploy.sh vets-service
./scripts/deploy.sh visits-service

# 3. AI & Admin Services
./scripts/deploy.sh genai-service
./scripts/deploy.sh admin-server

# 4. API Gateway (Public Entry Point)
./scripts/deploy.sh api-gateway
```

### Step 4.2: Application End-to-End Validation
```bash
# 1. Verify all 8 microservice pods are 1/1 Running with 0 restarts
kubectl get pods -n petclinic-dev

# 2. Get AWS ALB DNS URL
ALB_URL=$(aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[0].DNSName" --output text)
echo "Public Website URL: http://${ALB_URL}/"

# 3. Verify HTTP 200 OK on Homepage
curl.exe -i "http://${ALB_URL}/"
```

---

## 📊 Summary Checklist

- [x] **Teardown**: Ingress -> `terraform destroy dev` -> `terraform destroy bootstrap` -> AWS CLI zero verification.
- [x] **Provisioning**: Bootstrap apply -> Dev apply -> `aws eks update-kubeconfig` -> 5 nodes `Ready`.
- [x] **Platform Add-ons**: ESO installed -> AWS LB Controller installed -> Ingress applied -> ALB URL generated.
- [x] **Application Deploy**: All 8 microservices deployed via `./scripts/deploy.sh` -> All 8 pods `1/1 Running` -> HTTP 200 OK verified.
