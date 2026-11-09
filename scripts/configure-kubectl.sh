#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

CLUSTER="$(terraform output -raw cluster_name)"

aws eks update-kubeconfig \
  --region ap-south-1 \
  --name "$CLUSTER"

kubectl get nodes -o wide
