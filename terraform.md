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

This will:
1. Create the `openclaw` namespace
2. Generate a gateway token
3. Create PVCs for config and workspace
4. Deploy the gateway
5. Create a LoadBalancer service

## Configuration

### Basic Configuration

Create a `terraform.tfvars` file:

```hcl
namespace = "openclaw"
container_image = "ghcr.io/openclaw/openclaw:latest"
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

```hcl
config_storage_size = "5Gi"
workspace_storage_size = "20Gi"
```

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

By default, the onboarding job is not created (to prevent accidental runs). To run onboarding:

```hcl
# terraform.tfvars
create_onboarding_job = true
```

Or run it once:

```bash
terraform apply -var="create_onboarding_job=true"
```

When prompted during onboarding:
- Gateway bind: lan
- Gateway auth: token
- Gateway token: (use the output from `terraform output onboarding_token`)
- Tailscale exposure: Off
- Install Gateway daemon: No

## Commands

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

## Running CLI Commands

To run OpenClaw CLI commands via Terraform, use the `cli_commands` variable:

```hcl
# terraform.tfvars
cli_commands = {
  "login"  = "providers login"
  "status" = "channels status"
}
```

```bash
terraform apply
```

Note: After the job completes, remove it from `cli_commands` to re-apply.

## Outputs

After deployment, Terraform outputs:

```bash
terraform output namespace         # openclaw
terraform output gateway_token     # [sensitive - use terraform output gateway_token ]
terraform output onboarding_token  # Token for onboarding
terraform output gateway_service   # Service name and type
terraform output config_pvc        # openclaw-config-pvc
terraform output workspace_pvc     # openclaw-workspace-pvc
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
# terraform.tfvars
namespace               = "openclaw-dev"
container_image         = "my-registry/openclaw:dev"
gateway_replicas        = 1
service_type            = "NodePort"
create_onboarding_job   = true
```

## Documentation

- Full docs: https://docs.openclaw.ai
- Providers: https://docs.openclaw.ai/providers
- Gateway configuration: https://docs.openclaw.ai/configuration