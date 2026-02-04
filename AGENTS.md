# AGENTS.md

This file guides agentic coding agents working in the OpenClaw Kubernetes deployment repository.

## Build/Lint/Test Commands

This is an infrastructure-as-code repository with no traditional test suite. Key commands:

### Terraform (Primary IaC)
```bash
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
kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
kubectl apply -f config-pvc.yaml
kubectl apply -f workspace-pvc.yaml
kubectl apply -f onboarding-job.yaml
kubectl attach -n openclaw openclaw-onboarding -i -c onboard  # Run interactive onboarding
kubectl delete job -n openclaw openclaw-onboarding --ignore-not-found=true
kubectl apply -f gateway-deployment.yaml
kubectl apply -f gateway-service.yaml
```

### Scripts
```bash
./setup.sh                    # Full interactive setup
./tools.sh status             # Check deployment status
./tools.sh logs               # View gateway logs
./generate-manifest.sh        # Generate bundled YAML
./terraform-quickstart.sh     # Quick Terraform deployment
```

### Validation
No automated linting. Verify YAML syntax with `kubectl apply --dry-run=client -f <file>`.

## Code Style Guidelines

### Terraform (.tf)
- **Structure**: YAML files are single source of truth; Terraform uses `yamldecode` to parse them
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
- **Variables**: Provide defaults using `${VAR:-default}` pattern
- **Output**: Use `echo "==> Action"` prefix for user-facing messages
- **Function naming**: snake_case (*e.g.*, `generate_token`, `require_cmd`)
- **Dependency checking**: Verify commands exist before using them
- **Namespace**: Use `${OPENCLAW_NAMESPACE:-openclaw}` for flexibility
- **Image references**: Use `${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}` and `${OPENCLAW_BUSYBOX_IMAGE:-busybox:1.36}`

### General Conventions
- **Secrets**: Never commit real tokens. Use placeholder `"replace-with-generated-token"`
- **Git ignore**: Exclude `.terraform/`, `*.tfstate`, `*statefile*`, `.terraform.lock.hcl`
- **Comments**: Minimal; code should be self-documenting
- **Documentation**: Keep README.md and terraform.md in sync for user-facing docs
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
- `setup.sh` - Correct order
- `manifests.tf` - Via `depends_on` chain
- Manual kubectl - Must apply onboarding-job.yaml before gateway-deployment.yaml