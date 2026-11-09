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
# EKS ARM64 / AMD64 Platform Automation with Karpenter

![AWS](https://img.shields.io/badge/Cloud-AWS-orange)
![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5)
![Karpenter](https://img.shields.io/badge/Autoscaling-Karpenter-purple)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)
![Architecture](https://img.shields.io/badge/Architecture-ARM64%20%7C%20AMD64-green)
![Platform](https://img.shields.io/badge/Platform-Amazon%20EKS-blue)

A practical, beginner-friendly implementation of **Karpenter-based Kubernetes node provisioning on Amazon EKS**, using Terraform, Kubernetes manifests, AWS IAM, and automation scripts.

This project demonstrates how to build and operate an EKS platform that can dynamically provision both ARM64 and AMD64 EC2 worker nodes according to application requirements.

It covers infrastructure preparation, Karpenter installation and configuration, NodePools, EC2NodeClasses, NodeClaims, scheduling, scaling, consolidation, troubleshooting, and cost management.

---

# Table of Contents

1. [Project Overview](#1-project-overview)
2. [What Is Karpenter?](#2-what-is-karpenter)
3. [Why Do We Need Karpenter?](#3-why-do-we-need-karpenter)
4. [Karpenter vs Cluster Autoscaler](#4-karpenter-vs-cluster-autoscaler)
5. [Architecture](#5-architecture)
6. [Important Karpenter Concepts](#6-important-karpenter-concepts)
7. [ARM64 vs AMD64](#7-arm64-vs-amd64)
8. [Project Directory Structure](#8-project-directory-structure)
9. [Prerequisites](#9-prerequisites)
10. [Prepare Your Workstation](#10-prepare-your-workstation)
11. [Understand the Existing EKS Cluster](#11-understand-the-existing-eks-cluster)
12. [Understand AWS IAM Requirements](#12-understand-aws-iam-requirements)
13. [Install and Configure Karpenter](#13-install-and-configure-karpenter)
14. [Configure EC2NodeClasses](#14-configure-ec2nodeclasses)
15. [Configure ARM64 and AMD64 NodePools](#15-configure-arm64-and-amd64-nodepools)
16. [Deploy a Test Workload](#16-deploy-a-test-workload)
17. [Understand the Provisioning Lifecycle](#17-understand-the-provisioning-lifecycle)
18. [Scheduling and Placement](#18-scheduling-and-placement)
19. [Karpenter Scaling and Consolidation](#19-karpenter-scaling-and-consolidation)
20. [Automation Scripts](#20-automation-scripts)
21. [Terraform Workflow](#21-terraform-workflow)
22. [Complete Validation Commands](#22-complete-validation-commands)
23. [Monitoring and Logs](#23-monitoring-and-logs)
24. [Troubleshooting Guide](#24-troubleshooting-guide)
25. [Security Best Practices](#25-security-best-practices)
26. [Cost Optimization](#26-cost-optimization)
27. [Production Considerations](#27-production-considerations)
28. [Learning Roadmap for Freshers](#28-learning-roadmap-for-freshers)
29. [Useful Karpenter Commands](#29-useful-karpenter-commands)
30. [Cleanup and Resource Protection](#30-cleanup-and-resource-protection)
31. [Official Documentation](#31-official-documentation)

---

# 1. Project Overview

## What are we building?

We are building an automated worker-node provisioning platform using:

- Amazon EKS
- AWS EC2
- Karpenter
- Terraform
- Kubernetes
- Helm
- AWS IAM
- ARM64 and AMD64 architectures

In a traditional Kubernetes cluster, administrators often maintain fixed worker-node groups. When the cluster needs additional capacity, the node group must scale.

Karpenter changes this approach.

It observes Kubernetes pods that cannot be scheduled, evaluates their requirements, selects suitable EC2 capacity, and provisions nodes dynamically.

When nodes are no longer required, Karpenter can consolidate or remove them according to the configured disruption policy.

## Project objectives

1. Automate Kubernetes worker-node provisioning.
2. Support ARM64 and AMD64 architectures.
3. Use different EC2 instance families for different workloads.
4. Automatically provision nodes when pods cannot be scheduled.
5. Reduce unnecessary EC2 costs through consolidation.
6. Configure NodePools with resource limits.
7. Automate infrastructure preparation with Terraform.
8. Validate node provisioning using real Kubernetes workloads.
9. Provide operational commands for monitoring and troubleshooting.

## Project environment

The demonstrated environment uses:

| Component | Configuration |
|---|---|
| Cloud | AWS |
| Region | ap-south-1 |
| Kubernetes | Amazon EKS |
| Cluster | eks-arm64-platform |
| Operating system | Amazon Linux 2023 |
| ARM64 instance example | t4g.small |
| AMD64 instance example | t3.small |
| Infrastructure as Code | Terraform |
| Package management | Helm |
| Node provisioning | Karpenter |
| Workstation | WSL Ubuntu |

The example cluster and instance types describe the demonstrated environment. For another AWS account, replace these values with compatible resources.

**Important:** This repository is designed to work with an existing EKS platform. Do not recreate or destroy an existing EKS cluster just to follow the examples.

---

# 2. What Is Karpenter?

Karpenter is an open-source Kubernetes node lifecycle management and autoscaling project.

It automatically manages worker-node capacity based on Kubernetes workload requirements.

### Simple explanation

Imagine your Kubernetes cluster has two worker nodes.

You deploy an application requiring more CPU and memory than the available nodes can provide.

The Kubernetes scheduler cannot place the pod.

The pod becomes unschedulable.

Karpenter detects this condition, evaluates the pod requirements, and requests an appropriate EC2 instance from AWS.

The EC2 instance joins the EKS cluster as a Kubernetes worker node.

The pending pod can then be scheduled.

When the workload is removed, Karpenter can consolidate or terminate the unused capacity according to the NodePool configuration.

### Karpenter workflow

```text
Developer deploys application
           |
           v
     Kubernetes Pod
           |
           v
    Kubernetes Scheduler
           |
           v
  Pod cannot be scheduled?
           |
           v
    Karpenter Controller
           |
           v
 Evaluate Pod Requirements
           |
           v
 Select compatible NodePool
           |
           v
     EC2NodeClass
           |
           v
      AWS EC2 API
           |
           v
     Launch EC2 Instance
           |
           v
   EC2 joins EKS Cluster
           |
           v
   Kubernetes schedules Pod
           |
           v
        Application
```

Karpenter does not replace the Kubernetes scheduler. It supplies additional node capacity so the scheduler can place workloads.

---

# 3. Why Do We Need Karpenter?

Consider a cluster with a fixed worker-node group.

If application demand increases, the administrator may need to increase the node-group desired capacity.

This creates additional operational work and can result in unused capacity.

Karpenter provides a more workload-driven approach.

### Without Karpenter

- Fixed node groups.
- Manual capacity planning.
- Additional node-group configuration.
- Possible overprovisioning.
- Slower reaction to changing workloads.

### With Karpenter

- Dynamic node provisioning.
- Workload-driven capacity.
- Flexible EC2 instance selection.
- Architecture-aware scheduling.
- Automated consolidation.
- Resource limits through NodePools.

Karpenter is particularly useful when workloads have different CPU, memory, architecture, zone, or instance-type requirements.

---

# 4. Karpenter vs Cluster Autoscaler

| Feature | Cluster Autoscaler | Karpenter |
|---|---|---|
| Scaling mechanism | Adjusts node-group size | Provisions individual nodes |
| Main configuration | Node groups and ASGs | NodePools and NodeClasses |
| Instance selection | Usually tied to configured groups | Evaluates compatible capacity |
| Workload requirements | Uses node-group capacity | Evaluates pod scheduling constraints |
| Consolidation | Primarily node-group scaling down | Workload-aware consolidation |
| Architecture | Depends on configured groups | Can use architecture constraints |
| AWS integration | ASG-based | EC2 provisioning integration |

Both tools solve Kubernetes capacity problems, but their provisioning models are different.

Avoid running two autoscaling systems that independently control the same capacity without a deliberate design.

---

# 5. Architecture

## High-level AWS architecture

```text
                     AWS CLOUD
                         |
                         v
                 Amazon EKS Cluster
                         |
          +--------------+--------------+
          |                             |
          v                             v
   Bootstrap Node                Karpenter Controller
   Managed Node Group             Helm Deployment
          |                             |
          |                             |
          |                       AWS IAM Permissions
          |                             |
          |                             v
          |                       AWS EC2 APIs
          |                             |
          |              +--------------+--------------+
          |              |                             |
          |              v                             v
          |        ARM64 NodePool                AMD64 NodePool
          |              |                             |
          |              v                             v
          |        EC2NodeClass                  EC2NodeClass
          |              |                             |
          |              v                             v
          |          t4g.small                       t3.small
          |              |                             |
          +--------------+--------------+--------------+
                                         |
                                         v
                              Kubernetes Worker Nodes
                                         |
                                         v
                                Application Pods
```

## Main components

### Amazon EKS

Provides the Kubernetes control plane and API server.

### Bootstrap node

A stable node provides capacity for essential cluster services, including the Karpenter controller.

A practical design keeps the controller on capacity that does not depend on the same Karpenter pool it manages.

### Karpenter controller

Observes pending pods, evaluates scheduling constraints, and coordinates EC2 provisioning.

### AWS IAM

Allows Karpenter to perform the AWS operations required for node provisioning.

### EC2NodeClass

Defines AWS-specific node configuration such as:

- AMI selection.
- IAM node role.
- Subnet discovery.
- Security-group discovery.
- Storage configuration.
- Metadata options.

### NodePool

Defines the allowed node characteristics and provisioning policies.

### NodeClaim

Represents a requested node and its provisioning lifecycle.

---

# 6. Important Karpenter Concepts

These concepts are essential for interviews and practical operations.

## 6.1 NodePool

A NodePool defines which types of nodes Karpenter is allowed to provision.

It controls:

- CPU architecture.
- Operating system.
- EC2 instance types.
- Instance families.
- Availability zones.
- Capacity types.
- Taints and labels.
- Resource limits.
- Disruption policies.
- Node expiration.

Example:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-pool
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - arm64

        - key: kubernetes.io/os
          operator: In
          values:
            - linux

        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand

        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t4g.small

      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: eks-arm64-platform

      expireAfter: 720h

  limits:
    cpu: "2"

  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 2m
```

This is an educational example. Confirm that the referenced EC2NodeClass exists and that the instance type is available in the selected subnets and Availability Zones before applying.

## 6.2 EC2NodeClass

An EC2NodeClass provides AWS-specific configuration.

Example:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: eks-arm64-platform
spec:
  role: KarpenterNodeRole-YOUR_CLUSTER_NAME

  amiSelectorTerms:
    - alias: al2023@YOUR_COMPATIBLE_AMI_VERSION

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: YOUR_CLUSTER_NAME

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: YOUR_CLUSTER_NAME
```

Replace the placeholders with the actual IAM role, AMI alias, cluster name, and discovery tags.

## 6.3 NodeClaim

A NodeClaim is a Karpenter resource representing a node that Karpenter intends to provision.

It provides lifecycle information such as:

- Instance type.
- Zone.
- Capacity type.
- Launch status.
- Registration status.
- Initialization status.
- Readiness.

Useful commands:

```bash
kubectl get nodeclaims

kubectl describe nodeclaim NODECLAIM_NAME

kubectl get nodeclaims -o yaml
```

## 6.4 Consolidation

Consolidation is Karpenter's mechanism for reducing unnecessary capacity.

For example:

- A node becomes empty.
- Workloads can fit on other nodes.
- A less expensive node can replace existing capacity.

Common policies:

| Policy | Behavior |
|---|---|
| `WhenEmpty` | Considers empty nodes |
| `WhenEmptyOrUnderutilized` | Considers empty and underutilized nodes |

Use a conservative policy when running workloads that should not be disrupted unnecessarily.

## 6.5 Expiration

`expireAfter` controls the maximum lifetime of nodes provisioned through a NodePool.

Example:

```yaml
expireAfter: 720h
```

This is 30 days.

Expiration is a disruption mechanism and should be planned with application availability and PodDisruptionBudgets in mind.

## 6.6 Resource limits

NodePool limits restrict how much capacity Karpenter can provision.

Example:

```yaml
limits:
  cpu: "2"
```

This prevents the NodePool from provisioning unlimited CPU capacity.

Limits are especially important in development and credit-limited AWS environments.

---

# 7. ARM64 vs AMD64

Modern AWS EC2 supports multiple processor architectures.

## AMD64

AMD64 is the x86-64 architecture.

Example instance families:

- T3
- M5
- C5
- R5

## ARM64

ARM64 is the 64-bit ARM architecture.

AWS Graviton processors use ARM64.

Example instance families:

- T4g
- M6g
- C6g
- R6g

## Why use both?

Different workloads may have different architecture requirements.

For example:

| Workload | Architecture |
|---|---|
| ARM-compatible Node.js service | ARM64 |
| Legacy x86 application | AMD64 |
| Multi-architecture Docker image | ARM64 or AMD64 |
| Architecture-specific binary | Matching architecture |

### Important Docker requirement

A container image must support the architecture of the node on which it runs.

For multi-platform builds:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t YOUR_ECR_REPOSITORY:latest \
  --push .
```

Verify the image manifest:

```bash
docker buildx imagetools inspect \
  YOUR_ECR_REPOSITORY:latest
```

A Docker image built only for AMD64 should not be assumed to run natively on ARM64.

---

# 8. Project Directory Structure

```text
eks-arm64-platform-automation/
│
├── README.md
│
├── configs/
│
├── terraform/
│
├── kubernetes/
│
├── scripts/
│
├── deploy-nodepools.sh
│
├── generate-project.sh
│
├── implement-core.sh
│
└── .gitignore
```

## Directory purpose

| Directory/File | Purpose |
|---|---|
| `configs/` | Configuration files and platform settings |
| `terraform/` | AWS infrastructure and IAM-related Terraform configuration |
| `kubernetes/` | Kubernetes and Karpenter manifests |
| `scripts/` | Supporting automation scripts |
| `deploy-nodepools.sh` | NodePool deployment automation |
| `generate-project.sh` | Project-generation automation |
| `implement-core.sh` | Core implementation automation |
| `.gitignore` | Excludes Terraform state and local secrets |

The exact inputs and side effects of each script should be reviewed from its source before execution.

---

# 9. Prerequisites

Before starting, you should understand the following:

### Linux

- Basic commands.
- Shell scripting.
- File permissions.
- Environment variables.
- Processes and services.

### AWS

- IAM users and roles.
- VPC.
- Public and private subnets.
- Security groups.
- EC2.
- EKS.
- ECR.

### Kubernetes

- Pods.
- Deployments.
- Services.
- Namespaces.
- Nodes.
- Node selectors.
- Taints and tolerations.
- RBAC.
- Resource requests and limits.

### Terraform

- Providers.
- Variables.
- Outputs.
- Resources.
- Data sources.
- State.
- Plan and apply.

---

# 10. Prepare Your Workstation

The following commands assume Ubuntu or WSL Ubuntu.

Update packages:

```bash
sudo apt update
sudo apt upgrade -y
```

Install common utilities:

```bash
sudo apt install -y \
  curl \
  wget \
  unzip \
  git \
  jq \
  gettext-base \
  python3 \
  python3-pip
```

Verify:

```bash
git --version
jq --version
python3 --version
```

## Install AWS CLI

Use the official AWS CLI installation instructions:

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

Verify:

```bash
aws --version
```

## Install kubectl

Follow the official Kubernetes installation instructions:

https://kubernetes.io/docs/tasks/tools/

Verify:

```bash
kubectl version --client
```

## Install eksctl

Follow:

https://eksctl.io/installation/

Verify:

```bash
eksctl version
```

## Install Helm

Follow:

https://helm.sh/docs/intro/install/

Verify:

```bash
helm version
```

## Install Terraform

Follow:

https://developer.hashicorp.com/terraform/install

Verify:

```bash
terraform version
```

## Verify all tools

```bash
aws --version
kubectl version --client
eksctl version
helm version
terraform version
git --version
jq --version
```

---

# 11. Understand the Existing EKS Cluster

Configure your AWS identity:

```bash
aws sts get-caller-identity
```

Set environment variables:

```bash
export AWS_REGION="ap-south-1"
export CLUSTER_NAME="eks-arm64-platform"
```

Check the EKS cluster:

```bash
aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Name:name,Status:status,Version:version}' \
  --output table
```

Configure kubectl:

```bash
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"
```

Check Kubernetes:

```bash
kubectl cluster-info

kubectl get nodes -o wide

kubectl get namespaces

kubectl get pods -A
```

Check architecture:

```bash
kubectl get nodes \
  -L kubernetes.io/arch
```

Check existing worker nodes:

```bash
kubectl get nodes \
  -o custom-columns=NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type
```

Check EKS add-ons:

```bash
aws eks list-addons \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME"
```

Check the EKS authentication mode:

```bash
aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.accessConfig'
```

**Do not create another EKS cluster if you are following the existing-cluster implementation.**

---

# 12. Understand AWS IAM Requirements

Karpenter needs AWS permissions to provision EC2 instances and manage the node lifecycle.

There are two important identities.

## 12.1 Karpenter controller identity

The controller needs permissions for operations such as:

- Discovering EC2 instance types.
- Discovering subnets and security groups.
- Launching EC2 instances.
- Managing relevant EC2 resources.
- Passing the configured node IAM role.
- Integrating with EKS where required.
- Handling interruption events when configured.

AWS workload identity can be configured using IRSA or EKS Pod Identity, depending on the installation method and supported configuration.

## 12.2 Karpenter node identity

New EC2 worker nodes need an IAM role that allows them to register with EKS and access required AWS services.

Do not confuse the controller role with the worker-node role.

### Verify existing roles

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `Karpenter`)].RoleName' \
  --output table
```

Check the Karpenter controller service account:

```bash
kubectl get serviceaccount karpenter \
  -n kube-system \
  -o yaml
```

Check IAM Pod Identity associations:

```bash
aws eks list-pod-identity-associations \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME"
```

Check IRSA configuration if used:

```bash
kubectl get serviceaccount karpenter \
  -n kube-system \
  -o jsonpath='{.metadata.annotations}'
```

Review the trust policy and permissions before changing an existing IAM role.

---

# 13. Install and Configure Karpenter

For a new cluster, follow the official Karpenter Getting Started guide.

Official guide:

https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/

For an existing cluster, first inspect what is already installed.

```bash
helm list -n kube-system

kubectl get deployment -n kube-system | grep karpenter

kubectl get pods -n kube-system | grep karpenter

kubectl get crd | grep karpenter
```

Check the installed chart:

```bash
helm get values karpenter \
  -n kube-system
```

Check the controller:

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --tail=100
```

If Karpenter is not installed, use the official installation guide for your EKS version and chosen AWS identity method.

Do not blindly install a second controller into an existing cluster.

### Helm installation concepts

Karpenter is distributed as a Helm chart.

The installation process generally includes:

1. Create the controller IAM permissions.
2. Create the worker-node IAM role.
3. Configure the EKS authentication mechanism.
4. Install the Karpenter chart.
5. Configure the controller.
6. Create an EC2NodeClass.
7. Create at least one NodePool.
8. Deploy a test workload.

The controller needs to run on reliable cluster capacity. Do not make its only hosting capacity dependent on a NodePool that it manages.

---

# 14. Configure EC2NodeClasses

First inspect the existing configuration:

```bash
kubectl get ec2nodeclasses

kubectl describe ec2nodeclass eks-arm64-platform
```

An EC2NodeClass defines how Karpenter launches AWS EC2 instances.

Important fields:

| Field | Purpose |
|---|---|
| `role` | Worker-node IAM role |
| `amiSelectorTerms` | AMI selection |
| `subnetSelectorTerms` | Subnet discovery |
| `securityGroupSelectorTerms` | Security-group discovery |
| `blockDeviceMappings` | Root and data storage |
| `metadataOptions` | Instance metadata configuration |

### Verify subnet discovery

```bash
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --query 'Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}' \
  --output table
```

### Verify security-group discovery

```bash
aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName}' \
  --output table
```

The selectors must match the resources in the intended cluster. Incorrect discovery tags are a common reason for provisioning failures.

---

# 15. Configure ARM64 and AMD64 NodePools

This project uses separate NodePools to demonstrate architecture-aware capacity.

## ARM64 NodePool

Example requirements:

```yaml
requirements:
  - key: kubernetes.io/arch
    operator: In
    values:
      - arm64

  - key: kubernetes.io/os
    operator: In
    values:
      - linux

  - key: karpenter.sh/capacity-type
    operator: In
    values:
      - on-demand
```

For a Graviton instance:

```yaml
- key: node.kubernetes.io/instance-type
  operator: In
  values:
    - t4g.small
```

## AMD64 NodePool

Example requirements:

```yaml
requirements:
  - key: kubernetes.io/arch
    operator: In
    values:
      - amd64

  - key: kubernetes.io/os
    operator: In
    values:
      - linux

  - key: karpenter.sh/capacity-type
    operator: In
    values:
      - on-demand
```

Example instance type:

```yaml
- key: node.kubernetes.io/instance-type
  operator: In
  values:
    - t3.small
```

The correct EC2NodeClass reference must be included in each NodePool.

### Important scheduling relationship

A NodePool allows Karpenter to provision capacity.

A pod requests the capacity it needs.

The two sets of requirements must be compatible.

For example, an ARM64-only pod cannot run on an AMD64-only NodePool.

---

# 16. Deploy a Test Workload

A test workload proves that Karpenter can provision real capacity.

Before deploying, inspect existing nodes and NodePools:

```bash
kubectl get nodes -o wide

kubectl get nodepools

kubectl get nodeclaims
```

## ARM64 test manifest

Create:

```bash
cat <<'EOF' > arm64-test.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: karpenter-smoke
---
apiVersion: v1
kind: Pod
metadata:
  name: arm64-provisioning-test
  namespace: karpenter-smoke
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
    karpenter.sh/nodepool: arm64-pool
  containers:
    - name: test
      image: public.ecr.aws/docker/library/busybox:1.36
      command:
        - sh
        - -c
        - sleep 3600
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
  restartPolicy: Never
EOF
```

Apply:

```bash
kubectl apply -f arm64-test.yaml
```

Monitor:

```bash
kubectl get pods \
  -n karpenter-smoke \
  -w
```

In another terminal:

```bash
kubectl get nodeclaims -w
```

Check the nodes:

```bash
kubectl get nodes \
  -L kubernetes.io/arch,karpenter.sh/nodepool
```

Check the actual architecture:

```bash
kubectl exec \
  -n karpenter-smoke \
  arm64-provisioning-test \
  -- uname -m
```

Expected ARM64 result:

```text
aarch64
```

## AMD64 test

Use a similar workload with:

```yaml
nodeSelector:
  kubernetes.io/arch: amd64
  karpenter.sh/nodepool: amd64-pool
```

Use an AMD64-compatible image.

Verify:

```bash
kubectl exec \
  -n karpenter-smoke \
  amd64-provisioning-test \
  -- uname -m
```

Expected result:

```text
x86_64
```

### Resource-limit warning

A NodePool may already be at its CPU limit.

For example, a `t3.small` consumes 2 vCPUs. If the AMD64 NodePool has a CPU limit of 2, another node cannot be provisioned while the limit is fully consumed.

Check:

```bash
kubectl describe nodepool amd64-pool

kubectl describe nodepool arm64-pool
```

Do not increase limits without checking AWS quotas, available credits, and expected cost.

---

# 17. Understand the Provisioning Lifecycle

The provisioning process can be monitored through Kubernetes resources.

```text
Pod Created
    |
    v
Scheduler Finds No Suitable Capacity
    |
    v
Pod Marked Unschedulable
    |
    v
Karpenter Observes Pod
    |
    v
Scheduling Requirements Evaluated
    |
    v
Compatible NodePool Selected
    |
    v
NodeClaim Created
    |
    v
EC2 Instance Launched
    |
    v
Node Registers with EKS
    |
    v
Node Initialized
    |
    v
NodeClaim Ready
    |
    v
Pod Scheduled
```

Inspect the lifecycle:

```bash
kubectl get pods -A

kubectl get nodeclaims

kubectl describe nodeclaim NODECLAIM_NAME

kubectl get nodes -o wide
```

Useful NodeClaim conditions include:

- Launched
- Registered
- Initialized
- Ready

A Ready NodeClaim is strong evidence that the provisioned node successfully joined the cluster.

---

# 18. Scheduling and Placement

Karpenter considers the scheduling requirements of pending pods.

Important Kubernetes scheduling mechanisms:

## nodeSelector

```yaml
nodeSelector:
  kubernetes.io/arch: arm64
```

## nodeAffinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/arch
              operator: In
              values:
                - arm64
```

## Taints and tolerations

NodePool:

```yaml
taints:
  - key: workload
    value: special
    effect: NoSchedule
```

Pod:

```yaml
tolerations:
  - key: workload
    operator: Equal
    value: special
    effect: NoSchedule
```

## Resource requests

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
```

A pod's resource requests influence which nodes can accommodate it.

A pod can remain Pending if:

- No NodePool matches its requirements.
- NodePool limits are exhausted.
- EC2 capacity is unavailable.
- The instance type cannot satisfy the pod's resource requests.
- Taints are not tolerated.
- Required zones or architectures are unavailable.

---

# 19. Karpenter Scaling and Consolidation

## Scale up

Karpenter provisions new nodes when compatible unschedulable workloads require additional capacity.

Observe:

```bash
kubectl get pods -A

kubectl get nodeclaims

kubectl get nodes
```

## Scale down

Karpenter can remove unused nodes according to the configured disruption policy.

For a conservative NodePool:

```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 2m
```

This considers empty nodes after the configured delay.

## Consolidation behavior

Karpenter may:

1. Remove empty nodes.
2. Move workloads to existing free capacity.
3. Replace a node with cheaper compatible capacity.

Disruption is subject to scheduling constraints, PodDisruptionBudgets, NodePool budgets, and other safety rules.

### Important warning

Do not use this as a routine cleanup shortcut:

```bash
kubectl delete node NODE_NAME
```

Do not manually terminate the EC2 instance behind a NodeClaim.

Karpenter uses finalizers and termination logic to drain and terminate managed nodes safely.

Prefer removing the test workload and allowing the configured consolidation policy to act.

---

# 20. Automation Scripts

This repository includes automation entry points.

Before running them, inspect the scripts.

```bash
cd ~/eks-arm64-platform-automation

find . -maxdepth 3 -type f -print | sort
```

Check shell syntax:

```bash
bash -n deploy-nodepools.sh

bash -n generate-project.sh

bash -n implement-core.sh
```

Review script contents:

```bash
sed -n '1,240p' implement-core.sh

sed -n '1,240p' deploy-nodepools.sh

sed -n '1,240p' generate-project.sh
```

Review executable permissions:

```bash
ls -l *.sh
```

If a script is intended to be executable:

```bash
chmod +x implement-core.sh
chmod +x deploy-nodepools.sh
chmod +x generate-project.sh
```

Read the script's variables, paths, and actions before execution.

If a script modifies Terraform, IAM, EKS, or Kubernetes resources, inspect its plan and generated manifests first.

Do not assume that every script is safe to rerun.

---

# 21. Terraform Workflow

Move into the Terraform directory:

```bash
cd ~/eks-arm64-platform-automation/terraform
```

Inspect the files:

```bash
find . -maxdepth 3 -type f -print | sort
```

Initialize:

```bash
terraform init
```

Format:

```bash
terraform fmt -recursive
```

Validate:

```bash
terraform validate
```

Inspect current state:

```bash
terraform state list
```

Generate a plan:

```bash
terraform plan -out=platform.tfplan
```

Review the proposed changes before applying.

Apply only after confirming that the plan does not recreate or destroy existing shared infrastructure:

```bash
terraform apply platform.tfplan
```

Inspect outputs:

```bash
terraform output
```

### Terraform safety

Never commit:

```text
*.tfstate
*.tfstate.*
terraform.tfvars
*.tfplan
```

Do not run `terraform destroy` on a shared EKS platform without an explicit resource-by-resource review.

---

# 22. Complete Validation Commands

Use this checklist after implementing Karpenter.

## Cluster

```bash
kubectl cluster-info

kubectl get nodes -o wide

kubectl get namespaces
```

## Karpenter controller

```bash
kubectl get pods -n kube-system | grep karpenter

kubectl get deployment -n kube-system | grep karpenter

kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --tail=100
```

## Karpenter resources

```bash
kubectl get crd | grep karpenter

kubectl get nodepools

kubectl get ec2nodeclasses

kubectl get nodeclaims
```

## NodePool health

```bash
kubectl describe nodepool arm64-pool

kubectl describe nodepool amd64-pool
```

## Node architecture

```bash
kubectl get nodes \
  -L kubernetes.io/arch
```

## Node instance types

```bash
kubectl get nodes \
  -L node.kubernetes.io/instance-type
```

## NodePool ownership

```bash
kubectl get nodes \
  -L karpenter.sh/nodepool
```

## Workloads

```bash
kubectl get pods -A -o wide

kubectl get events \
  -A \
  --sort-by=.lastTimestamp
```

## AWS EC2 instances

```bash
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[].Instances[].{Instance:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,State:State.Name}' \
  --output table
```

This AWS query includes all matching EC2 instances in the region, not just Karpenter-managed instances. Identify ownership using tags and NodeClaim details.

---

# 23. Monitoring and Logs

## Karpenter controller logs

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --tail=200
```

Follow:

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  -f
```

## Controller events

```bash
kubectl get events \
  -n kube-system \
  --sort-by=.lastTimestamp
```

## Pod events

```bash
kubectl describe pod POD_NAME -n NAMESPACE
```

## Node events

```bash
kubectl describe node NODE_NAME
```

## NodeClaim events

```bash
kubectl describe nodeclaim NODECLAIM_NAME
```

## NodePool resources

```bash
kubectl get nodepools -o yaml
```

## EC2NodeClass resources

```bash
kubectl get ec2nodeclasses -o yaml
```

---

# 24. Troubleshooting Guide

This section is intended for practical incident investigation.

## Issue 1: Pod remains Pending

Check:

```bash
kubectl get pods -A

kubectl describe pod POD_NAME -n NAMESPACE
```

Look for:

- `FailedScheduling`
- `Insufficient cpu`
- `Insufficient memory`
- Untolerated taints
- Node affinity mismatch
- No matching NodePool

Then inspect:

```bash
kubectl get nodepools

kubectl get nodeclaims
```

Inspect Karpenter logs:

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --tail=200
```

## Issue 2: NodePool is not Ready

Check:

```bash
kubectl get nodepools

kubectl describe nodepool NODEPOOL_NAME
```

Check the EC2NodeClass:

```bash
kubectl describe ec2nodeclass EC2NODECLASS_NAME
```

Look for:

- Invalid NodeClass reference.
- Missing IAM role.
- Invalid requirements.
- Missing subnet selectors.
- Missing security-group selectors.

## Issue 3: NodeClaim remains in Launched state

Check:

```bash
kubectl describe nodeclaim NODECLAIM_NAME
```

Possible causes:

- Node cannot reach the EKS API endpoint.
- Worker-node IAM role is incorrect.
- EKS authentication configuration is missing.
- Node bootstrap is failing.
- Security-group or subnet routing is incorrect.
- AMI is incompatible.

Check EC2:

```bash
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids INSTANCE_ID
```

Check controller logs:

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --tail=200
```

## Issue 4: EC2 instance launches but does not register with EKS

Investigate:

1. Worker-node IAM role.
2. EKS access entry or authentication configuration.
3. Cluster endpoint connectivity.
4. Security groups.
5. Subnet route tables.
6. DNS and network connectivity.
7. AMI and bootstrap configuration.

Do not repeatedly delete NodeClaims without identifying the registration failure.

## Issue 5: No instance type is available

Check instance offerings:

```bash
aws ec2 describe-instance-type-offerings \
  --region "$AWS_REGION" \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=t4g.small" \
  --output table
```

Check EC2 quotas and regional capacity.

Try a compatible alternative instance type only after reviewing the NodePool constraints and budget.

## Issue 6: NodePool CPU limit reached

Check:

```bash
kubectl describe nodepool arm64-pool

kubectl describe nodepool amd64-pool
```

Inspect:

```bash
kubectl get nodeclaims

kubectl get nodes -o wide
```

A NodePool at its configured CPU limit cannot provision additional capacity beyond that limit.

Do not increase the limit blindly.

## Issue 7: ARM64 pod cannot run

Check the pod architecture constraint:

```bash
kubectl get pod POD_NAME \
  -n NAMESPACE \
  -o yaml
```

Check node architecture:

```bash
kubectl get nodes \
  -L kubernetes.io/arch
```

Check the image manifest:

```bash
docker buildx imagetools inspect IMAGE_NAME
```

The image must support ARM64.

## Issue 8: AMD64 pod cannot run

Check:

- AMD64 NodePool exists.
- AMD64 NodePool is Ready.
- The pod requests AMD64.
- NodePool CPU limit is not exhausted.
- Instance type is available.
- Image supports AMD64.

Commands:

```bash
kubectl get nodepools

kubectl describe nodepool amd64-pool

kubectl get nodeclaims
```

## Issue 9: Karpenter controller is crashing

Check:

```bash
kubectl get pods -n kube-system

kubectl describe pod \
  -n kube-system \
  -l app.kubernetes.io/name=karpenter
```

Inspect logs:

```bash
kubectl logs \
  -n kube-system \
  deployment/karpenter \
  --previous
```

Investigate:

- IAM permissions.
- Invalid controller configuration.
- Cluster API connectivity.
- Incompatible chart or controller version.
- Resource pressure on the controller node.

## Issue 10: Subnet discovery failure

Check:

```bash
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --output table
```

Check discovery tags:

```bash
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --output table
```

Ensure the EC2NodeClass selectors match the intended subnets.

## Issue 11: Security-group discovery failure

Check:

```bash
aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --output table
```

Review the selectors in the EC2NodeClass.

## Issue 12: Node is not consolidated

Check:

```bash
kubectl describe nodepool NODEPOOL_NAME

kubectl get nodeclaims

kubectl describe nodeclaim NODECLAIM_NAME
```

Possible reasons:

- Workloads still run on the node.
- Pods cannot be rescheduled elsewhere.
- PodDisruptionBudgets prevent eviction.
- Consolidation delay has not elapsed.
- Disruption budgets prevent the operation.
- The node is not eligible for the configured policy.

An `Unconsolidatable` event can be normal when a node still has workloads or cannot safely be consolidated.

## Issue 13: Terraform wants to destroy existing infrastructure

Stop before applying.

```bash
terraform plan
```

Review every proposed deletion and replacement.

Do not apply a destructive plan merely to resolve a Terraform error.

---

# 25. Security Best Practices

Karpenter has powerful AWS permissions. Secure its identities carefully.

1. Use least-privilege IAM permissions.
2. Separate controller IAM and node IAM roles.
3. Use IRSA or EKS Pod Identity according to the supported installation design.
4. Avoid long-lived AWS access keys in Kubernetes secrets.
5. Restrict discovery tags to the intended cluster.
6. Keep EC2 metadata configuration secure.
7. Use private subnets where appropriate.
8. Protect the EKS API endpoint.
9. Use Kubernetes RBAC for administrative access.
10. Protect Terraform state and credentials.
11. Review EC2 security groups.
12. Monitor Karpenter controller logs and events.
13. Use PodDisruptionBudgets for important workloads.
14. Use NodePool disruption budgets where appropriate.

---

# 26. Cost Optimization

Karpenter can improve infrastructure efficiency, but it does not guarantee that every workload becomes cheaper.

Actual cost depends on instance selection, runtime, storage, network traffic, and AWS pricing.

## Recommended controls

### 1. NodePool limits

Example:

```yaml
limits:
  cpu: "2"
```

### 2. Conservative consolidation

Example:

```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 2m
```

### 3. Use appropriate instance families

Consider ARM64 Graviton instances when applications and dependencies support them.

### 4. Use Spot where appropriate

Spot can reduce compute costs but introduces interruption risk.

Use it only for workloads that can tolerate interruption.

### 5. Avoid unnecessary test workloads

Remove test pods after completing validation.

### 6. Monitor AWS charges

Review:

- EC2 instances.
- EBS volumes.
- Elastic IPs.
- NAT gateways.
- Data transfer.
- Load balancers.
- EKS control-plane charges.

### 7. Review resource requests

Incorrectly high CPU or memory requests can cause unnecessary node provisioning.

---

# 27. Production Considerations

A production Karpenter platform should include:

- Multiple Availability Zones.
- Appropriate NodePool disruption budgets.
- PodDisruptionBudgets.
- Correct resource requests and limits.
- Controller high availability.
- Stable controller hosting capacity.
- Appropriate EC2 quotas.
- Reliable subnet and security-group discovery.
- IAM least privilege.
- Interruption handling for Spot capacity.
- Monitoring and alerting.
- Image architecture compatibility.
- Persistent storage topology planning.
- A documented upgrade process.
- Tested rollback and recovery procedures.

Do not copy a small development NodePool CPU limit directly into production.

Production capacity should be designed around application demand, availability objectives, and budget.

---

# 28. Learning Roadmap for Freshers

A beginner should follow these stages.

## Phase 1 – Linux and AWS fundamentals

Learn:

- Linux commands.
- AWS CLI.
- IAM.
- VPC.
- EC2.
- Subnets.
- Security groups.

Practice:

```bash
aws sts get-caller-identity

aws ec2 describe-instances

aws eks list-clusters \
  --region ap-south-1
```

## Phase 2 – Kubernetes fundamentals

Learn:

- Pods.
- Deployments.
- Services.
- Namespaces.
- Nodes.
- Scheduling.
- Node selectors.
- Taints and tolerations.
- RBAC.

Practice:

```bash
kubectl get nodes

kubectl get pods -A

kubectl get deployments -A

kubectl describe pod POD_NAME -n NAMESPACE
```

## Phase 3 – Terraform

Learn:

- Providers.
- Resources.
- Variables.
- Outputs.
- State.
- Plan.
- Apply.
- Modules.

Practice:

```bash
terraform init

terraform fmt

terraform validate

terraform plan
```

## Phase 4 – EKS

Learn:

- EKS cluster architecture.
- Managed node groups.
- EKS authentication.
- AWS networking.
- Worker-node registration.

Practice:

```bash
aws eks describe-cluster \
  --region ap-south-1 \
  --name YOUR_CLUSTER_NAME

kubectl get nodes -o wide
```

## Phase 5 – Karpenter

Learn:

- Controller.
- IAM integration.
- EC2NodeClass.
- NodePool.
- NodeClaim.
- Requirements.
- Provisioning.
- Consolidation.
- Disruption.

Practice:

```bash
kubectl get nodepools

kubectl get ec2nodeclasses

kubectl get nodeclaims

kubectl logs \
  -n kube-system \
  deployment/karpenter
```

## Phase 6 – ARM64 and AMD64

Learn:

- Processor architectures.
- Graviton instances.
- Docker multi-platform builds.
- Kubernetes architecture selectors.

Practice:

```bash
kubectl get nodes \
  -L kubernetes.io/arch
```

## Phase 7 – Production engineering

Learn:

- Cost optimization.
- Monitoring.
- Disruption budgets.
- PodDisruptionBudgets.
- Security.
- Troubleshooting.
- CI/CD automation.

---

# 29. Useful Karpenter Commands

### Controller

```bash
kubectl get pods -n kube-system | grep karpenter

kubectl get deployment karpenter -n kube-system

kubectl logs -n kube-system deployment/karpenter -f
```

### NodePools

```bash
kubectl get nodepools

kubectl describe nodepool arm64-pool

kubectl describe nodepool amd64-pool
```

### EC2NodeClasses

```bash
kubectl get ec2nodeclasses

kubectl describe ec2nodeclass eks-arm64-platform
```

### NodeClaims

```bash
kubectl get nodeclaims

kubectl get nodeclaims -o wide

kubectl describe nodeclaim NODECLAIM_NAME
```

### Kubernetes nodes

```bash
kubectl get nodes -o wide

kubectl get nodes \
  -L kubernetes.io/arch,karpenter.sh/nodepool,node.kubernetes.io/instance-type
```

### Events

```bash
kubectl get events -A \
  --sort-by=.lastTimestamp
```

### Resource usage

```bash
kubectl top nodes

kubectl top pods -A
```

---

# 30. Cleanup and Resource Protection

Before cleaning up a test, identify exactly which resources belong to it.

Check:

```bash
kubectl get pods -A

kubectl get nodeclaims

kubectl get nodes -o wide

kubectl get nodepools
```

For the ARM64 smoke-test workload:

```bash
kubectl delete pod \
  arm64-provisioning-test \
  -n karpenter-smoke
```

Allow Karpenter to consolidate according to the NodePool configuration.

For the entire test namespace, only if it contains no other required resources:

```bash
kubectl delete namespace karpenter-smoke
```

Do not manually terminate Karpenter-managed EC2 instances or delete NodeClaims as a shortcut.

### Critical protection rule

This project uses an existing EKS environment.

Never run these commands casually:

```bash
terraform destroy
eksctl delete cluster
aws eks delete-cluster
```

They can remove infrastructure that other applications depend on.

Always inspect the Terraform plan and AWS resource ownership before performing cleanup.

---

# 31. Official Documentation

Use official documentation as the primary reference. Karpenter APIs and installation instructions evolve, so verify compatibility with your EKS and Karpenter versions before implementation.

## Karpenter

- Main documentation: https://karpenter.sh/docs/
- Getting Started: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
- Concepts: https://karpenter.sh/docs/concepts/
- NodePools: https://karpenter.sh/docs/concepts/nodepools/
- NodeClasses: https://karpenter.sh/docs/concepts/nodeclasses/
- NodeClaims: https://karpenter.sh/docs/concepts/nodeclaims/
- Scheduling: https://karpenter.sh/docs/concepts/scheduling/
- Disruption: https://karpenter.sh/docs/concepts/disruption/
- Troubleshooting: https://karpenter.sh/docs/troubleshooting/

## AWS and EKS

- Amazon EKS: https://docs.aws.amazon.com/eks/
- EKS Best Practices – Karpenter: https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html
- AWS EC2: https://docs.aws.amazon.com/ec2/
- AWS IAM: https://docs.aws.amazon.com/iam/
- EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html

## Kubernetes

- Kubernetes Documentation: https://kubernetes.io/docs/
- Scheduling: https://kubernetes.io/docs/concepts/scheduling-eviction/
- Taints and Tolerations: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- Resource Management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- PodDisruptionBudgets: https://kubernetes.io/docs/tasks/run-application/configure-pdb/

## Terraform and Helm

- Terraform: https://developer.hashicorp.com/terraform/docs
- Helm: https://helm.sh/docs/

---

# Project Summary

This project demonstrates a practical implementation of dynamic Kubernetes worker-node provisioning on Amazon EKS using Karpenter.

It combines:

- AWS infrastructure.
- Terraform automation.
- Kubernetes scheduling.
- Karpenter NodePools.
- EC2NodeClasses.
- NodeClaims.
- ARM64 and AMD64 architectures.
- Dynamic provisioning.
- Consolidation.
- Cost controls.
- Operational troubleshooting.

**The main learning objective is to understand how a pending Kubernetes pod can trigger the provisioning of a suitable AWS EC2 instance, how that instance joins EKS, and how Karpenter manages its lifecycle afterward.**

Project: `eks-arm64-platform-automation`

Cloud: AWS

Region used in the demonstration: `ap-south-1`

Platform: Amazon EKS

Node provisioning: Karpenter

Infrastructure as Code: Terraform

Architectures: ARM64 and AMD64
