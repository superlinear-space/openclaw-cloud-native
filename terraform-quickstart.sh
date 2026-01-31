#!/bin/bash
set -euo pipefail

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

if [[ ! -f "terraform.tfvars" ]]; then
  cat <<'EOF' > terraform.tfvars
# OpenClaw Configuration
namespace = "openclaw"
container_image = "ghcr.io/openclaw/openclaw:latest"

# Gateway Settings
gateway_replicas = 1
gateway_bind = "lan"
service_type = "LoadBalancer"

# Storage
config_storage_size = "1Gi"
workspace_storage_size = "5Gi"

# Node Scheduling (label your nodes with: kubectl label nodes <node-name> openclaw-enabled=true)
node_selector = {
  "openclaw-enabled" = "true"
}

# Optional: Claude AI Integration
claude_ai_session_key = ""
claude_web_session_key = ""
claude_web_cookie = ""
EOF
  echo "Created terraform.tfvars with default configuration"
  echo "Edit it to customize your deployment"
  echo ""
  read -p "Press Enter to continue or Ctrl+C to edit terraform.tfvars first..."
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
  echo "  3. Run onboarding:"
  echo "     terraform apply -var='create_onboarding_job=true'"
  echo "     kubectl attach -n \$(terraform output namespace) openclaw-onboarding -i"
  echo ""
  echo "  Onboarding prompts:"
  echo "    - Gateway bind: lan"
  echo "    - Gateway auth: token"
  echo "    - Gateway token: \$(terraform output onboarding_token)"
  echo "    - Tailscale exposure: Off"
  echo "    - Install Gateway daemon: No"
else
  echo "Deployment cancelled"
fi