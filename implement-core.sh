#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

BACKUP="$ROOT/logs/core-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

for f in terraform/main.tf terraform/variables.tf terraform/outputs.tf terraform/providers.tf terraform/terraform.tfvars.example; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

cat > terraform/providers.tf <<'EOF'
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "eks-arm64-platform-automation"
      Environment = "learning"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "existing" {
  id = var.existing_vpc_id
}

data "aws_iam_role" "karpenter_node" {
  name = "KarpenterNodeRole-eks-arm64-platform"
}
EOF

cat > terraform/variables.tf <<'EOF'
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "eks-arm64-platform"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "existing_vpc_id" {
  description = "Existing VPC to reuse; Terraform will not own or delete it."
  type        = string
  default     = "vpc-0f1f4651b2947cf30"
}

variable "public_access_cidrs" {
  description = "Trusted IPv4 CIDRs allowed to access the EKS public API."
  type        = list(string)

  validation {
    condition = length(var.public_access_cidrs) > 0 && alltrue([
      for cidr in var.public_access_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "Provide at least one valid IPv4 CIDR."
  }
}

variable "bootstrap_instance_type" {
  type    = string
  default = "t4g.small"
}
EOF

cat > terraform/main.tf <<'EOF'
# ==========================================================
# REUSE EXISTING VPC
# ==========================================================

resource "aws_internet_gateway" "main" {
  vpc_id = data.aws_vpc.existing.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = data.aws_vpc.existing.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(data.aws_vpc.existing.cidr_block, 4, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                      = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                  = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                 = var.cluster_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ==========================================================
# EKS CONTROL PLANE IAM ROLE
# ==========================================================

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ==========================================================
# EKS CLUSTER
# ==========================================================

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_route_table_association.public
  ]

  tags = {
    Name = var.cluster_name
  }
}

# Tag the EKS-created cluster security group for Karpenter discovery.
resource "aws_ec2_tag" "cluster_discovery" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# ==========================================================
# EXISTING KARPENTER WORKER ROLE - REUSED
# ==========================================================

resource "aws_eks_node_group" "bootstrap" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-bootstrap"
  node_role_arn   = data.aws_iam_role.karpenter_node.arn
  subnet_ids      = aws_subnet.public[*].id

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.bootstrap_instance_type]
  disk_size      = 20

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload-tier = "bootstrap"
    architecture  = "arm64"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name = "${var.cluster_name}-bootstrap"
  }
}

# ==========================================================
# EKS ADDONS
# ==========================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [aws_eks_node_group.bootstrap]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [aws_eks_node_group.bootstrap]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.bootstrap]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.bootstrap]
}
EOF

cat > terraform/outputs.tf <<'EOF'
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "existing_vpc_id" {
  value = data.aws_vpc.existing.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "bootstrap_node_group" {
  value = aws_eks_node_group.bootstrap.node_group_name
}

output "karpenter_node_role_arn" {
  value = data.aws_iam_role.karpenter_node.arn
}
EOF

cat > terraform/terraform.tfvars.example <<'EOF'
aws_region          = "ap-south-1"
cluster_name        = "eks-arm64-platform"
kubernetes_version  = "1.36"
existing_vpc_id     = "vpc-0f1f4651b2947cf30"

# Replace with your actual public IPv4 CIDR.
public_access_cidrs = ["REPLACE_WITH_YOUR_PUBLIC_IP/32"]

bootstrap_instance_type = "t4g.small"
EOF

echo
echo "Core Terraform implementation files generated."
echo "Backup location: $BACKUP"
echo "Existing VPC and Karpenter worker IAM role are referenced, not recreated."
echo "No AWS resources were created or deleted."
