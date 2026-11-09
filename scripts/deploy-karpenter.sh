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
