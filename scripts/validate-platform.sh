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
