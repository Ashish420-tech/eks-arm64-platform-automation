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
