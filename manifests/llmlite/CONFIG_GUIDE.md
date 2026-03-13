# LiteLLM Configuration Guide

## Quick Start

### 1. Deploy LiteLLM

```bash
cd terraform
terraform apply -var="create_llmlite=true"
```

### 2. Initialize config.yaml

**Option A: Use the example config**

```bash
# Copy the example config to your PVC
kubectl cp manifests/llmlite/config.yaml.example \
  openclaw-llmlite-pod:/app/litellm-data/config.yaml \
  -n openclaw

# Edit the config
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  vi /app/litellm-data/config.yaml
```

**Option B: Create from scratch**

```bash
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  cat > /app/litellm-data/config.yaml << 'EOF'
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
EOF
```

### 3. Set API Keys

```bash
# Get current secret
kubectl get secret openclaw-llmlite -n openclaw -o yaml > llmlite-secret.yaml

# Edit and add your API keys (base64 encoded)
echo -n "your-openai-api-key" | base64
# Copy the output

# Update the secret
kubectl patch secret openclaw-llmlite -n openclaw \
  -p '{"data":{"OPENAI_API_KEY":"<base64-encoded-key>"}}'
```

### 4. Restart LiteLLM

```bash
kubectl rollout restart deployment/openclaw-llmlite -n openclaw
kubectl rollout status deployment/openclaw-llmlite -n openclaw
```

### 5. Test the Proxy

```bash
# Port forward
kubectl port-forward deployment/openclaw-llmlite -n openclaw 4000:4000

# Test request
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $(terraform output llmlite_master_key)" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## Configuration Options

### Minimal Config (config-minimal.yaml)

For quick testing with OpenAI only. See `manifests/llmlite/config-minimal.yaml`.

### Full Config (config.yaml.example)

Production-ready with all providers and features. See `manifests/llmlite/config.yaml.example`.

---

## Environment Variables

Set these via Kubernetes Secret `openclaw-llmlite`:

| Variable | Description | Required |
|----------|-------------|----------|
| `LITELLM_MASTER_KEY` | Admin key for proxy | Auto-generated |
| `LITELLM_SALT_KEY` | Salt key for database encryption (encrypts API keys & credentials) | Auto-generated (required for encryption) |
| `OPENAI_API_KEY` | OpenAI API key | For OpenAI models |
| `AZURE_API_BASE` | Azure OpenAI endpoint | For Azure models |
| `AZURE_API_KEY` | Azure OpenAI key | For Azure models |
| `ANTHROPIC_API_KEY` | Anthropic API key | For Claude models |
| `DATABASE_URL` | Database connection | Optional (SQLite default) |

### Example Secret Creation

```bash
# Create secret with all keys
kubectl create secret generic openclaw-llmlite -n openclaw \
  --from-literal=LITELLM_MASTER_KEY="sk-1234" \
  --from-literal=OPENAI_API_KEY="sk-..." \
  --from-literal=DATABASE_URL="sqlite:///app/litellm-data/prisma.db"
```
### Example Secret Creation
```bash
# Create secret with all keys
kubectl create secret generic openclaw-llmlite -n openclaw \
  --from-literal=LITELLM_MASTER_KEY="sk-1234" \
  --from-literal=LITELLM_SALT_KEY="$(openssl rand -base64 32)" \
  --from-literal=OPENAI_API_KEY="sk-..." \
  --from-literal=DATABASE_URL="postgresql://user:pass@host:5432/litellm"
```

⚠️ **Important**: `LITELLM_SALT_KEY` must be set **before** adding any models. Once set, do not change it or encrypted data will become unrecoverable.

---

## SQLite Database Setup

### Enable SQLite Persistence

```hcl
# terraform.tfvars
create_llmlite = true
llmlite_database_url = "sqlite:///app/litellm-data/prisma.db"
llmlite_config_storage_size = "100Mi"
```

### Verify SQLite is Working

```bash
# Check if prisma.db exists
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  ls -lh /app/litellm-data/

# Should see: prisma.db

# Check LiteLLM logs
kubectl logs deployment/openclaw-llmlite -n openclaw | grep -i "database"
```

### Database Encryption

LiteLLM supports encryption of sensitive data (API keys, credentials) at rest using `LITELLM_SALT_KEY`:

**What gets encrypted:**
- ✅ LLM API keys
- ✅ Provider credentials
- ✅ Configuration secrets

**What is NOT encrypted:**
- ❌ Spend logs (request/response data)
- ❌ Audit logs
- ❌ User/team metadata

**Enable encryption in Terraform:**
```hcl
# terraform.tfvars
create_llmlite = true
llmlite_database_url = "postgresql://user:pass@host:5432/litellm"
llmlite_salt_key = "$(openssl rand -base64 32)"  # Generate once, store securely
```

⚠️ **Critical**: Set `LITELLM_SALT_KEY` **before** adding any models. Never change it after initial setup.

For enhanced security, consider using external secret managers (AWS Secrets Manager, HashiCorp Vault) via LiteLLM's `key_management_system` setting.

### SQLite vs PostgreSQL

## Common Configurations

### Add Multiple Providers

```yaml
model_list:
  # OpenAI
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
  
  # Azure OpenAI
  - model_name: azure-gpt-4o
    litellm_params:
      model: azure/gpt-4o
      api_base: os.environ/AZURE_API_BASE
      api_key: os.environ/AZURE_API_KEY
      api_version: "2024-02-15-preview"
  
  # Anthropic
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
```

### Load Balancing

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
      rpm: 100  # Rate limit: 100 requests per minute
  
  - model_name: gpt-4o-backup
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY_2
  
router_settings:
  routing_strategy: simple-shuffle  # Distribute across models
```

### Caching with Redis

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis.openclaw.svc.cluster.local
    port: 6379
    password: os.environ/REDIS_PASSWORD
```

---

## Admin UI

LiteLLM includes a web UI for managing keys, users, and monitoring:

```bash
# Access via port-forward
kubectl port-forward deployment/openclaw-llmlite -n openclaw 4000:4000

# Open browser: http://localhost:4000
# Login with master key
```
### Exposing on Node IP

To expose LiteLLM on the node's IP address (for external access without LoadBalancer):

**Option 1: Using Terraform**
```hcl
# terraform.tfvars
llmlite_host_port = 4000  # Expose on node IP:port
```

**Option 2: Manual YAML Edit**
```yaml
# manifests/llmlite/deployment.yaml
ports:
- containerPort: 4000
  name: llmlite
  hostPort: 4000  # Add this line
```

**Access:** `http://<node-ip>:4000`

**Requirements:**
- Node must have label `openclaw-enabled: "true"`
- Port 4000 must be available on the node
- Firewall rules may need adjustment

---

## Admin UI
---

## Troubleshooting

### Config Not Loading

```bash
# Check if config.yaml exists
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  cat /app/litellm-data/config.yaml

# Check logs for errors
kubectl logs deployment/openclaw-llmlite -n openclaw | grep -i "config"
```

### Database Connection Failed

```bash
# Verify DATABASE_URL
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  echo $DATABASE_URL

# Check if prisma.db exists (for SQLite)
kubectl exec -it deployment/openclaw-llmlite -n openclaw -- \
  ls -lh /app/litellm-data/prisma.db

# Restart pod
kubectl delete pod -l app=openclaw-llmlite -n openclaw
```

### Model Not Found

1. Check model_name in config.yaml matches your request
2. Verify API keys are set correctly
3. Check LiteLLM logs for provider errors

---

## Resources

- **Official Docs**: https://docs.litellm.ai/docs/proxy/configs
- **Config Examples**: https://github.com/BerriAI/litellm/tree/main/deploy
- **Model Providers**: https://docs.litellm.ai/docs/providers
- **Virtual Keys**: https://docs.litellm.ai/docs/proxy/virtual_keys
- **Admin UI**: https://docs.litellm.ai/docs/proxy/ui
