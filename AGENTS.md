# AGENTS.md

This file guides agentic coding agents working in the OpenClaw Kubernetes deployment repository.

## Project Structure

```
openclaw-cloud-native/
├── README.md                    # Project entry point
├── Makefile                     # Convenient command entry points
├── AGENTS.md                    # This file
├── LICENSE
├── .gitignore
├── env.example                  # Configuration template
│
├── terraform/                   # Terraform configuration
│   ├── main.tf                  # Provider configuration
│   ├── variables.tf             # Input variables
│   ├── data.tf                  # Locals and YAML file reading
│   ├── outputs.tf               # Output values
│   ├── manifests.tf             # Kubernetes manifest resources
│   └── terraform.tfvars.example # Example variable values
│
├── manifests/                   # Kubernetes YAML manifests
│   ├── core/                    # Core OpenClaw components
│   │   ├── namespace.yaml
│   │   ├── secrets.yaml
│   │   ├── config-pvc.yaml
│   │   ├── workspace-pvc.yaml
│   │   ├── gateway-deployment.yaml
│   │   ├── gateway-service.yaml
│   │   └── onboarding-job.yaml
│   │
│   ├── browserless/             # Browserless browser automation
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   │
│   ├── searxng/                 # SearXNG search engine
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── pvc.yaml
│   │
│   ├── qdrant/                  # Qdrant vector database
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── pvc.yaml
│   │
│   └── bundled/                 # Generated bundled manifests
│       └── openclaw-k8s.yaml    # (gitignored, generated)
│
├── scripts/                     # Shell scripts
│   ├── setup.sh                 # Interactive setup script
│   ├── tools.sh                 # Operational tools
│   ├── generate-manifest.sh     # Generate bundled manifest
│   └── terraform-quickstart.sh  # Terraform quick start
│
└── docs/                        # Documentation
    └── terraform.md             # Terraform usage guide
```

## Build/Lint/Test Commands

This is an infrastructure-as-code repository with no traditional test suite. Key commands:

### Makefile (Recommended Entry Point)
```bash
make help          # Show available commands
make init          # Initialize Terraform
make plan          # Preview Terraform changes
make apply         # Deploy with Terraform
make setup         # Run interactive setup script
make status        # Show deployment status
make logs          # Follow gateway logs
make clean         # Remove generated files
```

### Terraform (Primary IaC)
```bash
cd terraform
terraform init                    # Initialize Terraform
terraform plan                    # Preview changes
terraform apply                   # Deploy resources
terraform destroy                 # Clean up resources
terraform output                  # View deployment outputs
terraform output gateway_token    # View sensitive outputs
terraform validate                # Validate Terraform syntax
```

**Sequential workflow for initial setup:**
```bash
cd terraform
# Step 1: Create onboarding job
terraform apply -var="create_onboarding_job=true" -var="create_gateway_deployment=false"

# Step 2: Complete onboarding
kubectl attach -n openclaw openclaw-onboarding -i -c onboard

# Step 3: Deploy gateway (doesn't start until onboarding completes)
terraform apply -var="create_onboarding_job=false" -var="create_gateway_deployment=true"
```

### Kubernetes Direct Deployment
**Critical**: Onboarding must run before gateway to initialize config.

```bash
kubectl apply -f manifests/core/namespace.yaml
kubectl apply -f manifests/core/secrets.yaml
kubectl apply -f manifests/core/config-pvc.yaml
kubectl apply -f manifests/core/workspace-pvc.yaml
kubectl apply -f manifests/core/onboarding-job.yaml
kubectl attach -n openclaw openclaw-onboarding -i -c onboard  # Run interactive onboarding
kubectl delete job -n openclaw openclaw-onboarding --ignore-not-found=true
kubectl apply -f manifests/core/gateway-deployment.yaml
kubectl apply -f manifests/core/gateway-service.yaml
```

### Scripts
```bash
./scripts/setup.sh                    # Full interactive setup
./scripts/tools.sh status             # Check deployment status
./scripts/tools.sh logs               # View gateway logs
./scripts/generate-manifest.sh        # Generate bundled YAML
./scripts/terraform-quickstart.sh     # Quick Terraform deployment
```

### Validation
No automated linting. Verify YAML syntax with `kubectl apply --dry-run=client -f <file>`.

## Code Style Guidelines

### Terraform (.tf)
- **Structure**: YAML files are single source of truth; Terraform uses `yamldecode` to parse them
- **Paths**: Terraform files read YAML from `../manifests/` directory using `${path.module}/../manifests/...`
- **Variable blocks**: Always include `description`, `type`, and `default` (if applicable)
- **Resource naming**: Descriptive format: `kubernetes_manifest.{component}`, `random_id.{purpose}`
- **String interpolation**: Use heredoc with `EOF` for multi-line YAML embedding
- **Formatting**: 2-space indentation, align equals signs
- **Provider versions**: Pin with `~>` (*e.g.*, `version = "~> 2.24"`)
- **Sensitive values**: Mark outputs with `sensitive = true`
- **Storage backend**: Supports both PVC (production) and HostPath (development) via `use_hostpath` variable

### Kubernetes YAML
- **Naming convention**: `openclaw-{component}` (*e.g.*, `openclaw-gateway`, `openclaw-config-pvc`)
- **Labels**: Include `app: openclaw-gateway` on pods/deployments; `app: openclaw` on namespace
- **Selectors**: Match labels using `matchLabels: {app: openclaw-gateway}`
- **Environment variables**: UPPERCASE_SNAKE_CASE
- **Node selector**: Default to `openclaw-enabled: "true"`, configurable via Terraform variable
- **Mount paths**: Use `/home/node/.openclaw` for config, `/home/node/.openclaw/workspace` for workspace
- **Separator**: Use `---` between manifest documents in bundled files

### Shell Scripts
- **Shebang**: `#!/usr/bin/env bash`
- **Error handling**: Always use `set -euo pipefail` at script start
- **REPO_ROOT**: Use `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` to find repo root
- **Variables**: Provide defaults using `${VAR:-default}` pattern
- **Output**: Use `echo "==> Action"` prefix for user-facing messages
- **Function naming**: snake_case (*e.g.*, `generate_token`, `require_cmd`)
- **Dependency checking**: Verify commands exist before using them
- **Namespace**: Use `${OPENCLAW_NAMESPACE:-openclaw}` for flexibility
- **Image references**: Use `${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}` and `${OPENCLAW_BUSYBOX_IMAGE:-busybox:1.36}`

### General Conventions
- **Plan files**: All planning documents must be placed in `.agent/plans/` directory
- **Secrets**: Never commit real tokens. Use placeholder `"replace-with-generated-token"`
- **Git ignore**: Exclude `.terraform/`, `*.tfstate`, `*statefile*`, `.terraform.lock.hcl`, `manifests/bundled/openclaw-k8s.yaml`
- **Comments**: Minimal; code should be self-documenting
- **Documentation**: Keep README.md and docs/terraform.md in sync for user-facing docs
- **Storage sizes**: Use format `"XGi"` (*e.g.*, `"1Gi"`, `"5Gi"`)
- **Port numbers**: Gateway `18789`, Bridge `18790`
- **Home directory**: Always set `HOME: /home/node` in containers
- **Storage backends**: 
  - **PVC** (production): Uses `persistentVolumeClaim` with `openclaw-config-pvc` and `openclaw-workspace-pvc`
  - **hostPath** (development): Uses `hostPath` with `DirectoryOrCreate` type, simpler but limited to single-node

### Error Handling in Scripts
- Check exit codes from kubectl commands
- Use `--ignore-not-found=true` for delete operations
- Provide helpful error messages when commands fail
- Use `|| true` for non-critical operations

### Testing Changes
Manually test deployment flow: generate token → create secrets → deploy → verify pods running
Check logs: `kubectl logs -n openclaw -l app=openclaw-gateway`
Verify services: `kubectl get svc -n openclaw`

### Important: Deployment Order

The onboarding job must run before the gateway deployment to ensure config is initialized in PVCs.

**Wrong order** (gateway starts with empty config):
1. Deploy gateway → Gateway runs with defaults
2. Run onboarding → Config written, but gateway already started

**Correct order** (gateway starts with config):
1. Run onboarding → Config written to PVCs
2. Deploy gateway → Gateway reads config from PVCs

This is handled automatically in:
- `scripts/setup.sh` - Correct order
- `terraform/manifests.tf` - Via `depends_on` chain
- Manual kubectl - Must apply manifests/core/onboarding-job.yaml before manifests/core/gateway-deployment.yaml
