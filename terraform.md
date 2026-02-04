# OpenClaw Cloud Native - Terraform Deployment

This directory contains Terraform configuration for deploying OpenClaw to Kubernetes.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- kubectl configured with cluster access
- Kubernetes cluster with sufficient resources

## Quick Start

```bash
terraform init
terraform apply
```

## Quick Start

**For development (with HostPath - simpler):**
```bash
terraform init
terraform apply -var="use_hostpath=true"
```

This uses host directories for storage - no PVCs required.

**For production (with PVCs - recommended):**
```bash
terraform init
terraform apply
```

This will:
1. Create the `openclaw` namespace
2. Generate a gateway token
3. Create PVCs for config and workspace (or use hostPath if enabled)
4. Deploy the gateway
5. Create a LoadBalancer service

**Important**: The onboarding job must run first to initialize config. Use one of these approaches:
- Use `setup.sh` for automated setup with proper ordering
- Or manually run onboarding before the first gateway deployment (see below)

## Configuration

### Basic Configuration

Create a `terraform.tfvars` file:

```hcl
namespace = "openclaw"
container_image = "ghcr.io/openclaw/openclaw:latest"
busybox_image = "busybox:latest"
gateway_replicas = 1
service_type = "LoadBalancer"
```

### Node Scheduling

```hcl
node_selector = {
  "openclaw-enabled" = "true"
  "node.kubernetes.io/instance-type" = "t3.large"
}
```

### Storage

**PVC (default for production):**
```hcl
use_hostpath = false
config_storage_size = "5Gi"
workspace_storage_size = "20Gi"
```

**HostPath (for development):**
```hcl
use_hostpath = true
fix_hostpath_permissions = true
config_hostpath = "/var/lib/openclaw/config"
workspace_hostpath = "/var/lib/openclaw/workspace"
```

When using hostPath, a `fix-permissions` init container will automatically:
- Set ownership to uid 1000 (the "node" user in the container)
- Set permissions to 700 (owner-only access)

This eliminates the need to manually configure permissions on host nodes.

### Service Type

```hcl
service_type = "NodePort"  # Options: LoadBalancer, NodePort, ClusterIP
```

### Claude AI Integration (Optional)

```hcl
claude_ai_session_key   = "your-session-key"
claude_web_session_key  = "your-web-session-key"
claude_web_cookie       = "your-cookie"
```

## Run Onboarding

### Option 1: Sequential Apply (Simplest for Initial Setup)

Run onboarding first, then deploy gateway:

```bash
# Step 1: Create onboarding job only
terraform apply -var="create_onboarding_job=true" -var="create_gateway_deployment=false"

# Step 2: Complete onboarding interactively
kubectl attach -n $(terraform output namespace) openclaw-onboarding -i -c onboard
```

When prompted during onboarding:
- Gateway bind: lan
- Gateway auth: token
- Gateway token: (use the output from `terraform output gateway_token`)
- Tailscale exposure: Off
- Install Gateway daemon: No

```bash
# Step 3: Clean up job (it will complete on its own, but you can delete)
kubectl delete job -n $(terraform output namespace) openclaw-onboarding --ignore-not-found=true

# Step 4: Deploy gateway (now with initialized config)
terraform apply -var="create_onboarding_job=false" -var="create_gateway_deployment=true"
```

### Option 2: Manual with Terraform

```bash
terraform apply -var="create_onboarding_job=true"
kubectl attach -n $(terraform output namespace) openclaw-onboarding -i -c onboard
```

When prompted during onboarding:
- Gateway bind: lan
- Gateway auth: token
- Gateway token: (use the output from `terraform output gateway_token`)
- Tailscale exposure: Off
- Install Gateway daemon: No

**IMPORTANT**: Complete onboarding before the gateway starts.

### Option 3: Existing Config (Production)

For production or greenfield deployments with existing config:

1. Copy existing config to PVCs (create a temporary job or use kubectl cp)
2. Set `create_onboarding_job = false`
3. Run `terraform apply`

## Commands

### Note: CLI Commands Feature

The `cli_commands` variable is defined but not yet implemented in the current version. To run CLI commands, use kubectl exec or the tools.sh script:

```bash
kubectl exec -n openclaw deployment/openclaw-gateway -- node dist/index.js providers status
# or
./tools.sh providers status
```

### Initial Deployment

```bash
terraform init
terraform plan
terraform apply
```

### Check Status

```bash
terraform output
kubectl get pods -n $(terraform output namespace)
kubectl get svc -n $(terraform output namespace)
```

### Update Configuration

```bash
terraform apply
```

### Scale Gateway

```bash
terraform apply -var="gateway_replicas=3"
```

### Destroy Resources

```bash
terraform destroy
```

### Configuration Changes

You can update any configuration variable and re-apply:

```bash
# Change container image
terraform apply -var="container_image=my-registry/openclaw:v2.0"

# Switch to hostPath
terraform apply -var="use_hostpath=true"

# Update namespace
terraform apply -var="namespace=openclaw-prod"
```

## Outputs

After deployment, Terraform outputs:

```bash
terraform output namespace           # openclaw
terraform output gateway_token       # [sensitive - use terraform output gateway_token ]
terraform output gateway_service     # Service name and type
terraform output storage_backend     # PVC or hostPath
terraform output storage_config_info # Storage configuration details
# PVC outputs (null if using hostPath):
terraform output config_pvc          # openclaw-config-pvc
terraform output workspace_pvc       # openclaw-workspace-pvc
# hostPath outputs (null if using PVC):
terraform output config_hostpath
terraform output workspace_hostpath
```

## Provider Setup

### Using Default Kubeconfig

Terraform will use `~/.kube/config` by default. Set `kubeconfig_path` if needed:

```hcl
kubeconfig_path = "/path/to/kubeconfig"
```

### Using Environment Variables

```bash
export KUBECONFIG=/path/to/kubeconfig
```

## Troubleshooting

### Job Stuck in Pending

```bash
kubectl get job -n $(terraform output namespace)
kubectl describe job <job-name> -n $(terraform output namespace)
```

### PVC Pending

```bash
kubectl get pvc -n $(terraform output namespace)
# Ensure your cluster has a default StorageClass
```

### Gateway Pod Not Starting

```bash
kubectl logs -n $(terraform output namespace) openclaw-gateway
kubectl describe pod -n $(terraform output namespace) -l app=openclaw-gateway
```

## Examples

### Minimal Deployment

```hcl
# terraform.tfvars
namespace = "openclaw"
```

### Production Deployment

```hcl
# terraform.tfvars
namespace               = "openclaw"
container_image         = "ghcr.io/openclaw/openclaw:latest"
busybox_image           = "busybox:latest"
gateway_replicas        = 3
service_type            = "LoadBalancer"
config_storage_size     = "10Gi"
workspace_storage_size  = "50Gi"
node_selector = {
  "openclaw-enabled"   = "true"
  "node.kubernetes.io/instance-type" = "c5.xlarge"
}
```

### Development Deployment

```hcl
# terraform.tfvars (with PVCs)
namespace               = "openclaw-dev"
container_image         = "my-registry/openclaw:dev"
gateway_replicas        = 1
service_type            = "NodePort"
create_onboarding_job   = true
```

```hcl
# terraform.tfvars (with hostPath - simpler for development)
namespace               = "openclaw-dev"
container_image         = "my-registry/openclaw:dev"
gateway_replicas        = 1
service_type            = "NodePort"
use_hostpath            = true
fix_hostpath_permissions = true
config_hostpath         = "/var/lib/openclaw/config"
workspace_hostpath      = "/var/lib/openclaw/workspace"
create_onboarding_job   = false  # Set to true for initial setup workflow
create_gateway_deployment = true
```

## Documentation

- Full docs: https://docs.openclaw.ai
- Providers: https://docs.openclaw.ai/providers
- Gateway configuration: https://docs.openclaw.ai/configuration