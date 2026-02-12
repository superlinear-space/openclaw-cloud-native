#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "OpenClaw Kubernetes - Terraform Quick Start"
echo "==========================================="
echo ""

check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: $1 is not installed" >&2
    echo "Install it from: https://www.terraform.io/downloads" >&2
    exit 1
  fi
}

check_cmd terraform
check_cmd kubectl

cd "$REPO_ROOT/terraform"

if [[ ! -f "terraform.tfvars.example" ]]; then
  echo "Error: terraform.tfvars.example not found"
  exit 1
fi

if [[ ! -f "terraform.tfvars.local" ]]; then
  cp terraform.tfvars.example terraform.tfvars.local
  echo "Created terraform.tfvars.local with default configuration"
  echo "Edit it to customize your deployment"
  echo ""
  read -p "Press Enter to continue or Ctrl+C to edit terraform.tfvars.local first..."
fi

echo "Initializing Terraform..."
terraform init

echo ""
echo "Checking Terraform plan..."
terraform plan

echo ""
read -p "Apply changes? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  terraform apply
  
  echo ""
  echo "Deployment complete!"
  echo ""
  echo "Outputs:"
  terraform output
  
  echo ""
echo "Next steps:"
  echo "  1. Check pod status: kubectl get pods -n \$(terraform output namespace)"
  echo "  2. Check service: kubectl get svc -n \$(terraform output namespace)"
  echo "  3. Run onboarding (for initial setup, use sequential applies):"
  echo "     terraform apply -var='create_onboarding_job=true' -var='create_gateway_deployment=false'"
  echo "     kubectl attach -n \$(terraform output namespace) openclaw-onboarding -i -c onboard"
  echo "     terraform apply -var='create_onboarding_job=false' -var='create_gateway_deployment=true'"
  echo ""
  echo "  Onboarding prompts:"
  echo "    - Gateway bind: lan"
  echo "    - Gateway auth: token"
  echo "    - Gateway token: \$(terraform output gateway_token)"
  echo "    - Tailscale exposure: Off"
  echo "    - Install Gateway daemon: No"
  echo ""
  echo "  Alternative: Use scripts/setup.sh for automated sequential setup"
else
  echo "Deployment cancelled"
fi
