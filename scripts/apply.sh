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
