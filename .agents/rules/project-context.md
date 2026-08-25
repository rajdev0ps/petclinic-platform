# Project Context & Architecture

## Application Overview

The Spring Petclinic Microservices ecosystem consists of 8 microservices:

| Service | Port | Needs MySQL | Description / Notes |
| :--- | :--- | :--- | :--- |
| `config-server` | 8888 | No | Centralized configuration server (starts first) |
| `discovery-server` | 8761 | No | Netflix Eureka service discovery (starts second) |
| `api-gateway` | 8080 | No | Public-facing gateway and routing |
| `customers-service` | 8081 | Yes | Customer and pet records management |
| `visits-service` | 8082 | Yes | Patient visit scheduling and logs |
| `vets-service` | 8083 | Yes | Veterinarian database with Caffeine cache |
| `genai-service` | 8084 | Optional | AI assistant integration (requires `OPENAI_API_KEY`) |
| `admin-server` | 9090 | No | Spring Boot Admin dashboard |

## Deployment & Target Infrastructure

- **Cloud Provider:** AWS (`eu-central-1`)
- **Container Registry:** AWS ECR (`{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service-name}`)
- **Target Platform:** `linux/arm64` (Graviton t4g nodes)
- **Database:** AWS RDS MySQL (`db.t4g.micro`, single-AZ free tier)
- **Orchestration:** AWS EKS + ArgoCD GitOps
- **Subnet Architecture:** All-public subnet design with Security Groups acting as perimeter control (cost optimization to avoid NAT Gateway charges, see ADR-0001).

## Environment Specifics

| Setting | Dev | Prod |
| :--- | :--- | :--- |
| K8s Namespace | `petclinic-dev` | `petclinic-prod` |
| State Key | `petclinic/dev/terraform.tfstate` | `petclinic/prod/terraform.tfstate` |
| Deploy Mode | ArgoCD Auto-Sync | ArgoCD Manual Sync |
| Service Replicas | 1 per service | 2+ per service with HPA |
