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
