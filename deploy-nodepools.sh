#!/usr/bin/env bash
set -Eeuo pipefail

export AWS_DEFAULT_REGION=ap-south-1
export AWS_PAGER=""

ROOT="$(cd "$(dirname "$0")" && pwd)"
KDIR="$ROOT/kubernetes/karpenter"

mkdir -p "$KDIR"

echo "===== CHECK KARPENTER CONTROLLER ====="
kubectl rollout status deployment/karpenter \
  -n kube-system --timeout=180s

echo "===== CHECK REQUIRED CRDS ====="
for crd in \
  ec2nodeclasses.karpenter.k8s.aws \
  nodepools.karpenter.sh \
  nodeclaims.karpenter.sh
do
  kubectl get crd "$crd"
done

echo "===== CHECK EXISTING WORKER ROLE ====="
aws iam get-role \
  --role-name KarpenterNodeRole-eks-arm64-platform \
  --query 'Role.Arn' --output text

echo "===== CREATE EC2 NODE CLASS ====="

cat > "$KDIR/ec2nodeclass.yaml" <<'EOF'
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: eks-arm64-platform
spec:
  role: KarpenterNodeRole-eks-arm64-platform

  amiSelectorTerms:
    - alias: al2023@latest

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-arm64-platform

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-arm64-platform

  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true

  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required

  detailedMonitoring: false

  tags:
    Project: eks-arm64-platform-automation
    Environment: learning
    ManagedBy: Karpenter
EOF

echo "===== CREATE ARM64 NODEPOOL ====="

cat > "$KDIR/nodepool-arm64.yaml" <<'EOF'
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-pool
spec:
  template:
    metadata:
      labels:
        architecture: arm64
        workload-architecture: arm64
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: eks-arm64-platform

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]

        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t4g.small"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

  limits:
    cpu: "2"

  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 2m
EOF

echo "===== CREATE AMD64 NODEPOOL ====="

cat > "$KDIR/nodepool-amd64.yaml" <<'EOF'
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: amd64-pool
spec:
  template:
    metadata:
      labels:
        architecture: amd64
        workload-architecture: amd64
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: eks-arm64-platform

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.small"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

  limits:
    cpu: "2"

  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 2m
EOF

echo "===== VALIDATE MANIFESTS ====="
kubectl apply --dry-run=server \
  -f "$KDIR/ec2nodeclass.yaml"

kubectl apply --dry-run=server \
  -f "$KDIR/nodepool-arm64.yaml"

kubectl apply --dry-run=server \
  -f "$KDIR/nodepool-amd64.yaml"

echo "===== APPLY EC2 NODE CLASS ====="
kubectl apply -f "$KDIR/ec2nodeclass.yaml"

echo "===== WAIT FOR EC2 NODE CLASS ====="
kubectl wait \
  --for=condition=Ready \
  ec2nodeclass/eks-arm64-platform \
  --timeout=300s

echo "===== APPLY BOTH NODEPOOLS ====="
kubectl apply -f "$KDIR/nodepool-arm64.yaml"
kubectl apply -f "$KDIR/nodepool-amd64.yaml"

echo "===== NODEPOOL STATUS ====="
kubectl get nodepools

echo "===== EC2 NODE CLASS STATUS ====="
kubectl get ec2nodeclasses

echo "===== KARPENTER LOGS ====="
kubectl logs deployment/karpenter \
  -n kube-system --tail=40

echo "===== COMPLETE ====="
