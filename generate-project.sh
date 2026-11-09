#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$ROOT/logs/file-backups-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$ROOT/logs"

write_file() {
    local path="$1"
    mkdir -p "$(dirname "$ROOT/$path")"

    if [[ -f "$ROOT/$path" ]]; then
        mkdir -p "$BACKUP/$(dirname "$path")"
        cp -p "$ROOT/$path" "$BACKUP/$path"
        echo "[BACKUP] $path"
    fi

    cat > "$ROOT/$path"
    echo "[CREATED] $path"
}

echo "Generating EKS ARM64 platform automation project..."

# ---------------------------------------------------------
# PROJECT METADATA
# ---------------------------------------------------------

write_file .gitignore <<'EOF'
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
terraform.tfvars
*.log
logs/
.DS_Store
EOF

write_file README.md <<'EOF'
# EKS ARM64 Platform Automation

Standalone Terraform-based AWS EKS and Karpenter learning platform.

## Architecture

- AWS region: ap-south-1
- EKS cluster: eks-arm64-platform
- VPC: 10.0.0.0/16
- Two public subnets
- One ARM64 managed bootstrap node
- Karpenter ARM64 and AMD64 NodePools
- EKS Pod Identity
- Helm-based Karpenter installation

## Cost considerations

This lab uses public subnets and does not create a NAT Gateway.
Worker nodes may receive public IPv4 addresses. Restrict access and
do not use this design as a production security baseline.

EKS, EC2, EBS, public IPv4, load balancers and data transfer can
generate charges. Review the Terraform plan before applying.

## Prerequisites

- AWS CLI v2
- Terraform >= 1.10
- kubectl
- Helm
- Docker (for application image builds)
- AWS credentials for the intended account

## Initial setup

1. Review terraform/terraform.tfvars.example.
2. Copy it to terraform/terraform.tfvars.
3. Set your public IPv4 CIDR with /32.
4. Run scripts/preflight-check.sh.
5. Run scripts/plan.sh.
6. Inspect the plan.
7. Run scripts/apply.sh and type APPLY when prompted.

## Kubernetes access

After Terraform provisioning:

    scripts/configure-kubectl.sh
    kubectl get nodes -o wide

## Karpenter

Karpenter installation requires its controller IAM policy,
IAM role, Pod Identity association, SQS interruption queue,
and service account to be configured correctly.

Do not install the controller until those prerequisites have
been implemented and verified.

The manifests in kubernetes/karpenter are configuration
templates, not proof that Karpenter is installed.

## Cleanup

No automatic destroy script is included. Review Terraform state,
AWS ownership and dependencies before any cleanup operation.
EOF

# ---------------------------------------------------------
# TERRAFORM ROOT
# ---------------------------------------------------------

write_file terraform/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
EOF

write_file terraform/providers.tf <<'EOF'
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
EOF

write_file terraform/variables.tf <<'EOF'
variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-arm64-platform"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version; verify regional support before applying"
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_access_cidrs" {
  description = "Trusted IPv4 CIDRs allowed to access the public EKS API"
  type        = list(string)

  validation {
    condition = length(var.public_access_cidrs) > 0 && alltrue([
      for cidr in var.public_access_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "Supply at least one valid trusted IPv4 CIDR."
  }
}

variable "bootstrap_instance_type" {
  description = "ARM64 bootstrap managed node group instance"
  type        = string
  default     = "t4g.small"
}

variable "bootstrap_desired_size" {
  type    = number
  default = 1
}

variable "bootstrap_min_size" {
  type    = number
  default = 1
}

variable "bootstrap_max_size" {
  type    = number
  default = 1
}
EOF

write_file terraform/terraform.tfvars.example <<'EOF'
aws_region       = "ap-south-1"
cluster_name     = "eks-arm64-platform"
kubernetes_version = "1.36"

vpc_cidr = "10.0.0.0/16"

# Replace with your own current public IPv4 CIDR.
# Example only; do not use this example address.
public_access_cidrs = ["REPLACE_WITH_YOUR_PUBLIC_IP/32"]

bootstrap_instance_type = "t4g.small"
bootstrap_desired_size  = 1
bootstrap_min_size      = 1
bootstrap_max_size      = 1
EOF

write_file terraform/main.tf <<'EOF'
# ---------------------------------------------------------
# VPC - PUBLIC SUBNET LEARNING LAB, NO NAT GATEWAY
# ---------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                              = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"          = "1"
    "karpenter.sh/discovery"          = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

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

# ---------------------------------------------------------
# EKS CLUSTER IAM ROLE
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# EKS BOOTSTRAP NODE IAM ROLE
# ---------------------------------------------------------

resource "aws_iam_role" "bootstrap_node" {
  name = "${var.cluster_name}-bootstrap-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bootstrap_worker" {
  role       = aws_iam_role.bootstrap_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "bootstrap_cni" {
  role       = aws_iam_role.bootstrap_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "bootstrap_ecr" {
  role       = aws_iam_role.bootstrap_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# ---------------------------------------------------------
# EKS CLUSTER
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# EKS MANAGED BOOTSTRAP NODE GROUP - ARM64
# ---------------------------------------------------------

resource "aws_eks_node_group" "bootstrap" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-bootstrap"
  node_role_arn   = aws_iam_role.bootstrap_node.arn
  subnet_ids      = aws_subnet.public[*].id

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.bootstrap_instance_type]
  disk_size      = 20

  scaling_config {
    desired_size = var.bootstrap_desired_size
    min_size     = var.bootstrap_min_size
    max_size     = var.bootstrap_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload-tier = "bootstrap"
    architecture  = "arm64"
  }

  depends_on = [
    aws_iam_role_policy_attachment.bootstrap_worker,
    aws_iam_role_policy_attachment.bootstrap_cni,
    aws_iam_role_policy_attachment.bootstrap_ecr
  ]

  tags = {
    Name = "${var.cluster_name}-bootstrap"
  }
}

# ---------------------------------------------------------
# EKS ADDONS
# ---------------------------------------------------------

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

write_file terraform/outputs.tf <<'EOF'
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "bootstrap_node_group" {
  value = aws_eks_node_group.bootstrap.node_group_name
}
EOF

# ---------------------------------------------------------
# KARPENTER KUBERNETES MANIFESTS
# ---------------------------------------------------------

write_file kubernetes/karpenter/service-account.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: karpenter
  namespace: kube-system
  labels:
    app.kubernetes.io/name: karpenter
    app.kubernetes.io/managed-by: terraform
EOF

write_file kubernetes/karpenter/ec2nodeclass.yaml <<'EOF'
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023

  # Create this role and its required policies before applying.
  role: KarpenterNodeRole-eks-arm64-platform

  amiSelectorTerms:
    - alias: al2023@latest

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-arm64-platform

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-arm64-platform

  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1
    httpTokens: required

  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true

  tags:
    Project: eks-arm64-platform-automation
    ManagedBy: Karpenter
EOF

write_file kubernetes/karpenter/nodepool-arm64.yaml <<'EOF'
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-graviton
spec:
  template:
    metadata:
      labels:
        architecture: arm64
        workload-tier: application
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]

        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t4g"]

        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["small"]

  limits:
    cpu: "8"

  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF

write_file kubernetes/karpenter/nodepool-amd64.yaml <<'EOF'
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: amd64-general
spec:
  template:
    metadata:
      labels:
        architecture: amd64
        workload-tier: application
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t3"]

        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["small"]

  limits:
    cpu: "8"

  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF

write_file kubernetes/karpenter/README.md <<'EOF'
# Karpenter prerequisites

Before applying these manifests:

1. Install Karpenter CRDs and controller.
2. Create the controller IAM role and complete controller permissions.
3. Create the EKS Pod Identity association for kube-system/karpenter.
4. Create the Karpenter node IAM role.
5. Ensure VPC subnets and security groups have the discovery tag.
6. Verify the Karpenter controller runs on the bootstrap node.

The EC2NodeClass uses a shared discovery configuration. NodePool
requirements select t4g.small for ARM64 and t3.small for AMD64.

Verify actual EC2 offering availability in ap-south-1 before testing.
EOF

# ---------------------------------------------------------
# KARPENTER HELM VALUES TEMPLATE
# ---------------------------------------------------------

write_file configs/karpenter-values.yaml <<'EOF'
replicas: 1

serviceAccount:
  create: false
  name: karpenter

settings:
  clusterName: eks-arm64-platform

# Configure interruptionQueue after creating the SQS queue
# and EventBridge rules for Karpenter interruption handling.

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 768Mi

nodeSelector:
  kubernetes.io/os: linux
  kubernetes.io/arch: arm64
  workload-tier: bootstrap
EOF

# ---------------------------------------------------------
# SCRIPTS
# ---------------------------------------------------------

write_file scripts/preflight-check.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "===== TOOL CHECK ====="
for cmd in aws terraform kubectl helm python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing command: $cmd"
    exit 1
  }
done

aws --version
terraform version
kubectl version --client
helm version

echo
echo "===== AWS IDENTITY ====="
aws sts get-caller-identity

echo
echo "===== AWS REGION ====="
aws configure get region

echo
echo "===== TERRAFORM INPUT ====="
if [[ ! -f terraform/terraform.tfvars ]]; then
  echo "Missing terraform/terraform.tfvars"
  echo "Copy terraform/terraform.tfvars.example and edit it."
  exit 1
fi

echo "Preflight checks passed. No AWS resources changed."
EOF

write_file scripts/plan.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/preflight-check.sh

cd terraform

terraform init
terraform fmt -recursive
terraform validate

terraform plan \
  -input=false \
  -out=platform.tfplan

terraform show platform.tfplan

echo
echo "Review the plan before running scripts/apply.sh."
EOF

write_file scripts/apply.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/preflight-check.sh
cd terraform

[[ -f platform.tfplan ]] || {
  echo "Plan not found. Run scripts/plan.sh first."
  exit 1
}

echo "Checking plan for deletion or replacement..."
terraform show -json platform.tfplan | python3 -c '
import json,sys
p=json.load(sys.stdin)
bad=[]
for r in p.get("resource_changes",[]):
    actions=r.get("change",{}).get("actions",[])
    if "delete" in actions:
        bad.append((r.get("address"),actions))
if bad:
    print("STOP: destructive changes found:")
    for address,actions in bad:
        print(address, actions)
    sys.exit(1)
print("No resource deletions or replacements found.")
'

echo
terraform show platform.tfplan
echo
read -r -p 'Type APPLY to provision the reviewed plan: ' answer

[[ "$answer" == "APPLY" ]] || {
  echo "Cancelled. No apply executed."
  exit 0
}

terraform apply -input=false platform.tfplan
terraform output
EOF

write_file scripts/configure-kubectl.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

CLUSTER="$(terraform output -raw cluster_name)"

aws eks update-kubeconfig \
  --region ap-south-1 \
  --name "$CLUSTER"

kubectl get nodes -o wide
EOF

write_file scripts/validate-platform.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

echo "===== CLUSTER ====="
kubectl cluster-info

echo
echo "===== NODES AND ARCHITECTURE ====="
kubectl get nodes \
  -L kubernetes.io/arch \
  -L workload-tier \
  -o wide

echo
echo "===== SYSTEM PODS ====="
kubectl get pods -n kube-system -o wide

echo
echo "===== KARPENTER CRDS ====="
kubectl get crd | grep -E 'karpenter|No resources' || true

echo
echo "===== KARPENTER PODS ====="
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter || true

echo
echo "Validation commands completed."
EOF

write_file scripts/deploy-karpenter.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER="eks-arm64-platform"
REGION="ap-south-1"
VERSION="${KARPENTER_VERSION:-1.15.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v helm >/dev/null
command -v kubectl >/dev/null
command -v aws >/dev/null

aws eks describe-cluster \
  --name "$CLUSTER" \
  --region "$REGION" >/dev/null

kubectl get nodes

echo
echo "This script requires the following to be configured first:"
echo "- Karpenter controller IAM policy and role"
echo "- EKS Pod Identity association"
echo "- SQS interruption queue and EventBridge rules if enabled"
echo "- Karpenter node IAM role"
echo "- Bootstrap node capacity for the controller"
echo
echo "This script does not create those AWS resources."

read -r -p "Type INSTALL-KARPENTER to continue: " answer
[[ "$answer" == "INSTALL-KARPENTER" ]] || exit 0

helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "$VERSION" \
  --namespace kube-system \
  --create-namespace \
  --values "$ROOT/configs/karpenter-values.yaml"

kubectl rollout status deployment/karpenter \
  -n kube-system \
  --timeout=5m

echo "Karpenter Helm deployment completed."
EOF

# ---------------------------------------------------------
# PERMISSIONS AND COMPLETION
# ---------------------------------------------------------

chmod +x "$ROOT"/scripts/*.sh

echo
echo "======================================================"
echo " PROJECT GENERATION COMPLETED"
echo "======================================================"
echo "Project: $ROOT"
echo
echo "Generated files:"
find "$ROOT" \
  -path "$ROOT/.git" -prune -o \
  -path "$ROOT/logs" -prune -o \
  -type f -print | sort

echo
echo "Backups, if any: $BACKUP"
echo
echo "No AWS resources were created or deleted."
