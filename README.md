# OpenClaw Kubernetes Deployment

Deploy OpenClaw to Kubernetes using the manifests in this directory. The default image is `ghcr.io/openclaw/openclaw:latest`.

## Project Structure

```
openclaw-cloud-native/
├── README.md                    # This file
├── Makefile                     # Convenient command entry points
├── terraform/                   # Terraform configuration
├── manifests/                   # Kubernetes YAML manifests
│   ├── core/                    # Core OpenClaw components
│   ├── browserless/             # Browserless browser automation
│   ├── searxng/                 # SearXNG search engine
│   ├── qdrant/                  # Qdrant vector database
│   ├── llmlite/                 # LiteLLM proxy
│   └── bundled/                 # Generated bundled manifests
├── scripts/                     # Shell scripts
└── docs/                        # Documentation
```

## Quick Start

### Option 1: Makefile (Recommended)
```bash
make help          # Show available commands
make init          # Initialize Terraform
make plan          # Preview changes
make apply         # Deploy with Terraform
make setup         # Run interactive setup script
make status        # Show deployment status
make logs          # Follow gateway logs
```

### Option 2: Terraform
```bash
cd terraform
terraform init
terraform apply
```

### Option 3: Direct kubectl
```bash
# Generate token
TOKEN=$(openssl rand -hex 32)

# Update token in secrets.yaml
sed -i "s/replace-with-generated-token/$TOKEN/" manifests/core/secrets.yaml

# Apply resources in correct order (onboarding before gateway!)
kubectl apply -f manifests/core/namespace.yaml
kubectl apply -f manifests/core/secrets.yaml
kubectl apply -f manifests/core/config-pvc.yaml
kubectl apply -f manifests/core/workspace-pvc.yaml
kubectl apply -f manifests/core/onboarding-job.yaml        # Run onboarding FIRST to initialize config
kubectl attach -n openclaw openclaw-onboarding -i -c onboard  # Attach and complete onboarding
kubectl delete job -n openclaw openclaw-onboarding --ignore-not-found=true  # Clean up
kubectl apply -f manifests/core/gateway-deployment.yaml     # THEN deploy gateway
kubectl apply -f manifests/core/gateway-service.yaml

# Label your nodes
kubectl label nodes <node-name> openclaw-enabled=true
```

**Important**: The onboarding job must run before the gateway deployment to ensure config is initialized.

### Option 4: Bundled YAML
```bash
./scripts/generate-manifest.sh
kubectl apply -f manifests/bundled/openclaw-k8s.yaml
```

### Option 5: Interactive Setup Script (Easiest)
```bash
# Production (with PVCs)
./scripts/setup.sh

# Development (with hostPath - simpler, no PVCs required)
export OPENCLAW_USE_HOSTPATH=true
export OPENCLAW_CONFIG_HOSTPATH=/var/lib/openclaw/config
export OPENCLAW_WORKSPACE_HOSTPATH=/var/lib/openclaw/workspace
./scripts/setup.sh
```

The `scripts/setup.sh` script automates the entire deployment:
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
cd terraform
terraform apply -var="create_onboarding_job=true"
kubectl attach -n openclaw openclaw-onboarding -i
```

### Outputs
```bash
cd terraform
terraform output namespace
terraform output gateway_token      # Sensitive
terraform output browserless_token  # Sensitive
terraform output searxng_secret     # Sensitive
terraform output qdrant_api_key     # Sensitive
terraform output llmlite_master_key # Sensitive
terraform output gateway_service
terraform output searxng_service
terraform output qdrant_service
terraform output llmlite_service
```

### Destroy
```bash
cd terraform
terraform destroy
```

## Manual Setup with Individual Resources

### Namespace
```bash
kubectl apply -f manifests/core/namespace.yaml
```

### Secrets
```bash
kubectl apply -f manifests/core/secrets.yaml
```

### PVCs
```bash
kubectl apply -f manifests/core/config-pvc.yaml
kubectl apply -f manifests/core/workspace-pvc.yaml
```

### Gateway Deployment
```bash
kubectl apply -f manifests/core/gateway-deployment.yaml
```

### Gateway Service
```bash
kubectl apply -f manifests/core/gateway-service.yaml
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
| `gateway_host_port` | `0` | Gateway host port to expose on node (0 = disabled) |
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
| `create_searxng` | `false` | Create SearXNG deployment |
| `searxng_image` | `docker.io/searxng/searxng:latest` | SearXNG container image |
| `searxng_replicas` | `1` | Number of SearXNG replicas |
| `searxng_port` | `8080` | SearXNG service port |
| `searxng_secret` | auto-generated | SearXNG secret key |
| `searxng_config_storage_size` | `100Mi` | SearXNG config PVC storage |
| `searxng_data_storage_size` | `500Mi` | SearXNG data PVC storage |
| `searxng_config_hostpath` | `/var/lib/openclaw/searxng/config` | Host path for SearXNG config (if hostPath) |
| `searxng_data_hostpath` | `/var/lib/openclaw/searxng/data` | Host path for SearXNG data (if hostPath) |
| `create_qdrant` | `false` | Create Qdrant deployment |
| `qdrant_image` | `docker.io/qdrant/qdrant:latest` | Qdrant container image |
| `qdrant_replicas` | `1` | Number of Qdrant replicas |
| `qdrant_http_port` | `6333` | Qdrant HTTP API port |
| `qdrant_grpc_port` | `6334` | Qdrant gRPC port |
| `qdrant_api_key` | auto-generated | Qdrant API key for authentication |
| `qdrant_config_storage_size` | `100Mi` | Qdrant config PVC storage |
| `qdrant_storage_size` | `5Gi` | Qdrant data PVC storage |
| `qdrant_config_hostpath` | `/var/lib/openclaw/qdrant/config` | Host path for Qdrant config (if hostPath) |
| `qdrant_storage_hostpath` | `/var/lib/openclaw/qdrant/storage` | Host path for Qdrant storage (if hostPath) |
| `create_llmlite` | `false` | Create LiteLLM deployment |
| `llmlite_image` | `docker.litellm.ai/berriai/litellm:main-latest` | LiteLLM container image |
| `llmlite_replicas` | `1` | Number of LiteLLM replicas |
| `llmlite_port` | `4000` | LiteLLM service port |
| `llmlite_master_key` | auto-generated | LiteLLM master key for authentication |
| `llmlite_config_storage_size` | `100Mi` | LiteLLM config PVC storage |
| `llmlite_config_hostpath` | `/var/lib/openclaw/llmlite/config` | Host path for LiteLLM config (if hostPath) |
| `llmlite_database_url` | `""` | Database URL for LiteLLM (optional) |
| `gateway_additional_hostpath_mounts` | `[]` | Additional hostPath mounts for gateway deployment |
| `kubeconfig_path` | `~/.kube/config` | Path to kubeconfig file |

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

### Core Components (`manifests/core/`)

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `openclaw` namespace |
| `secrets.yaml` | Holds gateway token and optional Claude keys |
| `config-pvc.yaml` | Persistent volume for config (1Gi) |
| `workspace-pvc.yaml` | Persistent volume for workspace (5Gi) |
| `gateway-deployment.yaml` | Gateway deployment with 1 replica |
| `gateway-service.yaml` | LoadBalancer service exposing ports 18789/18790 |
| `onboarding-job.yaml` | One-time job for initial onboarding |

### Optional Components

| Directory | Description |
|-----------|-------------|
| `manifests/browserless/` | Browserless browser automation deployment |
| `manifests/searxng/` | SearXNG search engine deployment |
| `manifests/qdrant/` | Qdrant vector database deployment |
| `manifests/llmlite/` | LiteLLM LLM proxy deployment |

### Generated

| File | Description |
|------|-------------|
| `manifests/bundled/openclaw-k8s.yaml` | Bundled single-file manifest (generated, gitignored) |

## SearXNG Local Search Engine

SearXNG is a privacy-respecting, self-hosted metasearch engine that aggregates results from multiple search engines.

### Enable SearXNG

**With Terraform:**
```bash
cd terraform
terraform apply -var="create_searxng=true"
```

**Or using tfvars:**
```hcl
create_searxng = true
searxng_replicas = 1
```

### Storage Options

**PVC (default for production):**
```hcl
create_searxng = true
searxng_config_storage_size = "100Mi"
searxng_data_storage_size = "500Mi"
```

**HostPath (for development):**
```hcl
create_searxng = true
use_hostpath = true
searxng_config_hostpath = "/var/lib/openclaw/searxng/config"
searxng_data_hostpath = "/var/lib/openclaw/searxng/data"
```

### Accessing SearXNG

Once deployed, SearXNG is available within the cluster at:
```
http://openclaw-searxng.<namespace>.svc.cluster.local:8080
```

Or from other pods in the same namespace:
```
http://openclaw-searxng:8080
```

### SearXNG Configuration

SearXNG configuration is stored in `/etc/searxng/settings.yml` inside the container. You can customize it by:

1. **Exec into the pod:**
   ```bash
   kubectl exec -it -n openclaw deployment/openclaw-searxng -- /bin/sh
   ```

2. **Edit settings.yml** and restart the pod

For more configuration options, see the [SearXNG documentation](https://docs.searxng.org/admin/settings/settings.html).

## Qdrant Vector Database

Qdrant is a high-performance vector database for AI applications, enabling similarity search and vector embeddings storage.

### Enable Qdrant

**With Terraform:**
```bash
cd terraform
terraform apply -var="create_qdrant=true"
```

**Or using tfvars:**
```hcl
create_qdrant = true
qdrant_replicas = 1
```

### Storage Options

**PVC (default for production):**
```hcl
create_qdrant = true
qdrant_config_storage_size = "100Mi"
qdrant_storage_size = "5Gi"
```

**HostPath (for development):**
```hcl
create_qdrant = true
use_hostpath = true
qdrant_config_hostpath = "/var/lib/openclaw/qdrant/config"
qdrant_storage_hostpath = "/var/lib/openclaw/qdrant/storage"
```

### Accessing Qdrant

Once deployed, Qdrant is available within the cluster at:

- **HTTP API**: `http://openclaw-qdrant.<namespace>.svc.cluster.local:6333`
- **gRPC API**: `http://openclaw-qdrant.<namespace>.svc.cluster.local:6334`

Or from other pods in the same namespace:
- **HTTP**: `http://openclaw-qdrant:6333`
- **gRPC**: `http://openclaw-qdrant:6334`

### Qdrant Authentication

Qdrant uses an API key for authentication. The API key is auto-generated and can be retrieved:

```bash
cd terraform
terraform output qdrant_api_key
```

When making requests, include the API key in the header:
```bash
curl -H "api-key: YOUR_API_KEY" http://openclaw-qdrant:6333/collections
```

### Qdrant Configuration

Qdrant configuration can be customized by:

1. **Environment variables** - Set in the deployment
2. **Configuration file** - Mounted at `/qdrant/config/production.yaml`

For more configuration options, see the [Qdrant documentation](https://qdrant.tech/documentation/guides/configuration/).

## LiteLLM (LLMLite) Proxy

LiteLLM is a lightweight LLM proxy server that provides a unified OpenAI-compatible API for 100+ LLM providers. It supports load balancing, cost tracking, and logging.

### Enable LiteLLM

**With Terraform:**
```bash
cd terraform
terraform apply -var="create_llmlite=true"
```

**Or using tfvars:**
```hcl
create_llmlite = true
llmlite_replicas = 1
```

### Storage Options

**PVC (default for production):**
```hcl
create_llmlite = true
llmlite_config_storage_size = "100Mi"
```

**HostPath (for development):**
```hcl
create_llmlite = true
use_hostpath = true
llmlite_config_hostpath = "/var/lib/openclaw/llmlite/data"
```

### Storage Purpose

The PVC/hostPath stores:
- `config.yaml` - LiteLLM configuration file (more secure than ConfigMap)
- `prisma.db` - SQLite database (optional, for lightweight persistence)
- Runtime data and logs

### Accessing LiteLLM

Once deployed, LiteLLM is available within the cluster at:
```
http://openclaw-llmlite.<namespace>.svc.cluster.local:4000
```

Or from other pods in the same namespace:
```
http://openclaw-llmlite:4000
```

### LiteLLM Configuration

LiteLLM requires a `config.yaml` file to define model configurations. You can create this configuration by:

1. **Create config in PVC:**
   ```bash
   kubectl exec -it -n openclaw deployment/openclaw-llmlite -- /bin/bash
   # Edit /app/config.yaml with your model configurations
   ```

2. **Example config.yaml:**
   ```yaml
   model_list:
     - model_name: azure-gpt-4o
       litellm_params:
         model: azure/<your-azure-model-deployment>
         api_base: os.environ/AZURE_API_BASE
         api_key: os.environ/AZURE_API_KEY
         api_version: "2025-01-01-preview"
   ```

3. **Set environment variables:**
   ```bash
   export AZURE_API_BASE="https://your-resource.openai.azure.com/"
   export AZURE_API_KEY="your-api-key"
   ```

### LiteLLM Authentication

LiteLLM uses a master key for authentication. The master key is auto-generated and can be retrieved:

```bash
cd terraform
terraform output llmlite_master_key
```

When making requests, include the master key in the Authorization header:
```bash
curl -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "azure-gpt-4o", "messages": [{"role": "user", "content": "Hello"}]}' \
  http://openclaw-llmlite:4000/chat/completions
```

### Database Support (Optional)

LiteLLM can optionally use a database for persistent storage of logs, spend tracking, and virtual keys:

```hcl
llmlite_database_url = "postgresql://user:password@host:5432/litellm"
```

### Exposing LiteLLM on Node IP (Optional)

By default, LiteLLM is only accessible within the cluster. To expose it on the node's IP address:

```hcl
# In terraform.tfvars
llmlite_host_port = 4000  # 0 = disabled (default), >0 = expose on node IP
```

After applying, access LiteLLM at `http://<node-ip>:4000`.

**Note:** Requires the `openclaw-enabled: "true"` node selector to match your node.

For more configuration options, see the [LiteLLM documentation](https://docs.litellm.ai/docs/).

## Tools Script

Use `./scripts/tools.sh` for common operations:
```bash
./scripts/tools.sh status        # Check deployment status
./scripts/tools.sh logs          # View gateway logs
./scripts/tools.sh providers login
./scripts/tools.sh providers add --provider telegram --token <token>
./scripts/tools.sh restart       # Restart gateway
./scripts/tools.sh delete        # Delete all resources
```

## Troubleshooting

### Pod not starting:
```bash
kubectl describe pod -n openclaw -l app=openclaw-gateway
./scripts/tools.sh logs
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
- Terraform guide: [`docs/terraform.md`](docs/terraform.md)
