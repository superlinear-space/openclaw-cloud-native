# OpenClaw Cloud Native

Deploy OpenClaw to Kubernetes. This repository provides production-ready Kubernetes manifests and tooling for running OpenClaw in cloud-native environments.

## Quick Start

```bash
./setup.sh
```

This script will:
1. Create namespace and secrets
2. Create PVCs for persistence
3. Deploy the gateway
4. Run interactive onboarding

## Manual Setup

If you prefer step-by-step control:

```bash
export OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"

kubectl apply -f namespace.yaml

kubectl create secret generic openclaw-config \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN"

kubectl apply -f config-pvc.yaml
kubectl apply -f workspace-pvc.yaml
kubectl apply -f gateway-deployment.yaml
kubectl apply -f gateway-service.yaml

kubectl wait --namespace=openclaw \
  --for=condition=ready pod \
  -l app=openclaw-gateway
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_NAMESPACE` | `openclaw` | Kubernetes namespace |
| `OPENCLAW_IMAGE` | `ghcr.io/openclaw/openclaw:latest` | Container image |
| `OPENCLAW_GATEWAY_TOKEN` | auto-generated | Gateway auth token |

### Optional Claude Keys

Add AI support by setting these before running setup:

```bash
export CLAUDE_AI_SESSION_KEY="your-key"
export CLAUDE_WEB_SESSION_KEY="your-session-key"
export CLAUDE_WEB_COOKIE="your-cookie"
```

## Prerequisites

- Kubernetes cluster with `kubectl` configured
- LoadBalancer support in your cluster
- Sufficient storage for PVCs

## Manifests

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `openclaw` namespace |
| `secrets.yaml` | Holds gateway token and optional Claude keys |
| `config-pvc.yaml` | Persistent volume for config (1Gi) |
| `workspace-pvc.yaml` | Persistent volume for workspace (5Gi) |
| `gateway-deployment.yaml` | Gateway deployment with 1 replica |
| `gateway-service.yaml` | LoadBalancer service exposing ports 18789/18790 |
| `cli-job.yaml` | Template for running CLI commands as Jobs |

## Tools Script

Use `./tools.sh` for common operations:

```bash
# Check deployment status
./tools.sh status

# View gateway logs
./tools.sh logs

# Run CLI commands
./tools.sh cli channels status

# Setup providers
./tools.sh providers login
./tools.sh providers add --provider telegram --token <token>

# Restart gateway
./tools.sh restart

# Delete all resources
./tools.sh delete
```

## Accessing the Service

The gateway is exposed via a LoadBalancer service. Get the external IP:

```bash
kubectl get svc openclaw-gateway -n openclaw
```

Use this IP with the gateway token to connect from your apps.

## Customization

### Change Image

```bash
export OPENCLAW_IMAGE=myregistry.com/openclaw:custom-tag
./setup.sh
```

### Change Namespace

```bash
export OPENCLAW_NAMESPACE=my-openclaw
./setup.sh
```

### Adjust PVC Sizes

Edit `config-pvc.yaml` and `workspace-pvc.yaml` before deployment.

### Use NodePort Instead of LoadBalancer

Edit `gateway-service.yaml` and change `type: LoadBalancer` to `type: NodePort`.

### Scale Gateway

Edit `gateway-deployment.yaml` and change `replicas: 1` to your desired replica count.

## Troubleshooting

**Pod not starting:**
```bash
kubectl describe pod -n openclaw -l app=openclaw-gateway
./tools.sh logs
```

**PVC pending:**
```bash
kubectl get pvc -n openclaw
# Ensure your cluster has a default StorageClass
```

**Onboarding stuck:**
```bash
kubectl delete job openclaw-onboarding -n openclaw
# Rerun setup or use tools.sh to run CLI commands
```

## Cleanup

```bash
# Using tools script
./tools.sh delete

# Or manually
kubectl delete namespace openclaw
```

## Production Considerations

- **Resource Limits**: Consider adding `resources` limits to `gateway-deployment.yaml` containers
- **Pod Disruption Budget**: Add a PDB to ensure availability during node maintenance
- **Health Checks**: The deployment includes standard Kubernetes probes
- **Security**: Secrets are used for sensitive data; consider using external secret management
- **Backup**: Backup PVC data regularly using your cluster's backup solution

## Related Projects

- **OpenClaw**: https://github.com/openclaw/openclaw
- **Documentation**: https://docs.openclaw.ai
- **Providers**: https://docs.openclaw.ai/providers
- **Gateway configuration**: https://docs.openclaw.ai/configuration

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- Issues: https://github.com/superlinear-space/openclaw-cloud-native/issues
- Discussions: https://github.com/superlinear-space/openclaw-cloud-native/discussions
- OpenClaw Community: https://docs.openclaw.ai/community