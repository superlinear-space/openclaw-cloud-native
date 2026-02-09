# OpenClaw Kubernetes Deployment

Deploy OpenClaw to Kubernetes using the manifests in this directory. The default image is `ghcr.io/openclaw/openclaw:latest`.

## Quick Start

### Option 1: Terraform (Recommended)
```bash
terraform init
terraform apply
```

### Option 2: Direct kubectl
```bash
# Generate token
TOKEN=$(openssl rand -hex 32)

# Update token in secrets.yaml
sed -i "s/replace-with-generated-token/$TOKEN/" secrets.yaml

# Apply resources in correct order (onboarding before gateway!)
kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
kubectl apply -f config-pvc.yaml
kubectl apply -f workspace-pvc.yaml
kubectl apply -f onboarding-job.yaml        # Run onboarding FIRST to initialize config
kubectl attach -n openclaw openclaw-onboarding -i -c onboard  # Attach and complete onboarding
kubectl delete job -n openclaw openclaw-onboarding --ignore-not-found=true  # Clean up
kubectl apply -f gateway-deployment.yaml     # THEN deploy gateway
kubectl apply -f gateway-service.yaml

# Label your nodes
kubectl label nodes <node-name> openclaw-enabled=true
```

**Important**: The onboarding job must run before the gateway deployment to ensure config is initialized.

### Option 3: Bundled YAML
```bash
./generate-manifest.sh
kubectl apply -f openclaw-k8s.yaml
```

### Option 4: Interactive Setup Script (Easiest)
```bash
# Production (with PVCs)
./setup.sh

# Development (with hostPath - simpler, no PVCs required)
export OPENCLAW_USE_HOSTPATH=true
export OPENCLAW_CONFIG_HOSTPATH=/var/lib/openclaw/config
export OPENCLAW_WORKSPACE_HOSTPATH=/var/lib/openclaw/workspace
./setup.sh
```

The `setup.sh` script automates the entire deployment:
- Generates a gateway token (or uses `OPENCLAW_GATEWAY_TOKEN`)
- Creates namespace and secrets
- Creates PVCs (or uses hostPath if enabled) for config and workspace
- Deploys gateway as a Deployment
- Creates LoadBalancer service
- Runs interactive onboarding
- Provides provider setup commands

Environment variables (optional):
```bash
export OPENCLAW_NAMESPACE="openclaw"
export OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
export OPENCLAW_BUSYBOX_IMAGE="busybox:latest"
export OPENCLAW_GATEWAY_TOKEN="your-token"  # auto-generated if not set
export OPENCLAW_USE_HOSTPATH="false"       # Use hostPath instead of PVC
export OPENCLAW_CONFIG_HOSTPATH="/var/lib/openclaw/config"
export OPENCLAW_WORKSPACE_HOSTPATH="/var/lib/openclaw/workspace"
export CLAUDE_AI_SESSION_KEY="optional-ai-key"
export OPENCLAW_NODE_SELECTOR='{"openclaw-enabled":"true"}'
```

## Terraform Usage

Terraform parses the existing YAML files using `yamldecode`, making the YAML files the single source of truth. This eliminates duplication between Terraform and YAML definitions.

### Configuration

Create `terraform.tfvars`:
```hcl
namespace = "openclaw"
container_image = "ghcr.io/openclaw/openclaw:latest"
gateway_replicas = 1
service_type = "LoadBalancer"
```

### Run Onboarding
```bash
terraform apply -var="create_onboarding_job=true"
kubectl attach -n openclaw openclaw-onboarding -i
```

### Outputs
```bash
terraform output namespace
terraform output gateway_token      # Sensitive
terraform output browserless_token  # Sensitive
terraform output gateway_service
```

### Destroy
```bash
terraform destroy
```

## Manual Setup with Individual Resources

### Namespace
```bash
kubectl apply -f namespace.yaml
```

### Secrets
```bash
kubectl apply -f secrets.yaml
```

### PVCs
```bash
kubectl apply -f config-pvc.yaml
kubectl apply -f workspace-pvc.yaml
```

### Gateway Deployment
```bash
kubectl apply -f gateway-deployment.yaml
```

### Gateway Service
```bash
kubectl apply -f gateway-service.yaml
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `namespace` | `openclaw` | Kubernetes namespace |
| `container_image` | `ghcr.io/openclaw/openclaw:latest` | Container image |
| `busybox_image` | `busybox:latest` | Busybox image for init containers |
| `gateway_token` | auto-generated | Gateway auth token |
| `browserless_token` | auto-generated | Browserless auth token |
| `gateway_replicas` | `1` | Number of gateway replicas |
| `gateway_bind` | `lan` | Gateway bind mode |
| `gateway_port` | `18789` | Gateway service port |
| `bridge_port` | `18790` | Bridge service port |
| `service_type` | `LoadBalancer` | Kubernetes service type |
| `use_hostpath` | `false` | Use hostPath instead of PVC (development) |
| `fix_hostpath_permissions` | `true` | Auto-fix hostPath permissions (chown 1000:1000, chmod 700) |
| `config_hostpath` | `/var/lib/openclaw/config` | Host path for config (if hostPath) |
| `workspace_hostpath` | `/var/lib/openclaw/workspace` | Host path for workspace (if hostPath) |
| `config_storage_size` | `1Gi` | Config PVC storage |
| `workspace_storage_size` | `5Gi` | Workspace PVC storage |
| `browserless_image` | `ghcr.io/browserless/chromium:latest` | Browserless container image |
| `browserless_replicas` | `1` | Number of browserless replicas |
| `browserless_port` | `3000` | Browserless service port |
| `browserless_token` | auto-generated | Browserless auth token |
| `create_browserless` | `false` | Create browserless deployment |

### Node Scheduling

The gateway deployment uses a node selector:
```yaml
nodeSelector:
  openclaw-enabled: "true"
```

Label your nodes:
```bash
kubectl label nodes <node-name> openclaw-enabled=true
```

## Manifests

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `openclaw` namespace |
| `secrets.yaml` | Holds gateway token and optional Claude keys |
| `browserless-deployment.yaml` | Browserless deployment (optional) |
| `browserless-service.yaml` | Browserless service (optional) |
| `config-pvc.yaml` | Persistent volume for config (1Gi) |
| `workspace-pvc.yaml` | Persistent volume for workspace (5Gi) |
| `gateway-deployment.yaml` | Gateway deployment with 1 replica |
| `gateway-service.yaml` | LoadBalancer service exposing ports 18789/18790 |
| `onboarding-job.yaml` | One-time job for initial onboarding |
| `cli-job.yaml` | Template for running CLI commands as jobs |
| `openclaw-k8s.yaml` | Bundled single-file manifest |

## Tools Script

Use `./tools.sh` for common operations:
```bash
./tools.sh status        # Check deployment status
./tools.sh logs          # View gateway logs
./tools.sh providers login
./tools.sh providers add --provider telegram --token <token>
./tools.sh restart       # Restart gateway
./tools.sh delete        # Delete all resources
```

## Troubleshooting

### Pod not starting:
```bash
kubectl describe pod -n openclaw -l app=openclaw-gateway
./tools.sh logs
```

### PVC pending:
```bash
kubectl get pvc -n openclaw
# Ensure your cluster has a default StorageClass
```

### Onboarding stuck:
```bash
kubectl delete job openclaw-onboarding -n openclaw
```

## Documentation

- Full docs: https://docs.openclaw.ai
- Providers: https://docs.openclaw.ai/providers
- Gateway configuration: https://docs.openclaw.ai/configuration