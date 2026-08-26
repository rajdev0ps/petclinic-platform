variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster and node group (public subnets)"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster control plane"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

variable "node_instance_types" {
  description = "List of EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for EKS nodes (AL2023_ARM_64_STANDARD for Graviton t4g instances on K8s >= 1.33)"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"

  validation {
    condition     = contains(["AL2_ARM_64", "AL2_x86_64", "AL2023_ARM_64_STANDARD", "AL2023_x86_64_STANDARD"], var.node_ami_type)
    error_message = "node_ami_type must be a valid EKS AMI type."
  }
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 5
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 5
}

variable "node_disk_size" {
  description = "EBS root volume size in GB for each node"
  type        = number
  default     = 20
}

# ─── Add-on versions ─────────────────────────────────────────────────────────
# Pin to specific releases; update deliberately after testing in dev first.
# To find supported versions: aws eks describe-addon-versions --kubernetes-version <ver>

variable "addon_coredns_version" {
  description = "Pinned version of the CoreDNS EKS add-on"
  type        = string
  default     = "v1.14.3-eksbuild.2"
}

variable "addon_kube_proxy_version" {
  description = "Pinned version of the kube-proxy EKS add-on (must match cluster K8s version)"
  type        = string
  default     = "v1.35.3-eksbuild.11"
}

variable "addon_vpc_cni_version" {
  description = "Pinned version of the vpc-cni EKS add-on"
  type        = string
  default     = "v1.22.1-eksbuild.2"
}

variable "addon_ebs_csi_version" {
  description = "Pinned version of the aws-ebs-csi-driver EKS add-on"
  type        = string
  default     = "v1.60.1-eksbuild.1"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for the EKS cluster log group"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value."
  }
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API server endpoint. Default allows all — restrict to known IPs for better security."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
