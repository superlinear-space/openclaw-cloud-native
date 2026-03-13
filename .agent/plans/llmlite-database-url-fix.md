# LiteLLM DATABASE_URL Bug Fix

## Problem

When `llmlite_database_url` is not set (empty string), the Kubernetes Secret was created with an empty `DATABASE_URL` key:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-llmlite
type: Opaque
data:
  LITELLM_MASTER_KEY: <base64-encoded-key>
  DATABASE_URL: ""  # ← Problem: Empty string instead of missing
```

This caused LiteLLM to see `DATABASE_URL` environment variable as an empty string, which could lead to:
- LiteLLM attempting to connect to a database with an invalid URL
- Error: "Not connected to DB!" or "URL must start with postgresql://"
- Confusion about whether database mode is enabled

## Solution

Using Terraform's `merge()` function to conditionally include `DATABASE_URL` only when the user provides a value:

```hcl
data = merge(
  {
    LITELLM_MASTER_KEY = local.llmlite_master_key
  },
  var.llmlite_database_url != "" ? {
    DATABASE_URL = var.llmlite_database_url
  } : {}
)
```

## Behavior Comparison

### Before Fix

**Scenario 1: No database URL provided**
```hcl
llmlite_database_url = ""
```

Generated Secret:
```yaml
data:
  LITELLM_MASTER_KEY: "xxx"
  DATABASE_URL: ""  # ← Empty string (problematic)
```

Environment variable in pod:
```bash
DATABASE_URL=""  # Set but empty
```

LiteLLM behavior: ⚠️ May fail with "Not connected to DB!"

---

**Scenario 2: Database URL provided**
```hcl
llmlite_database_url = "postgresql://user:pass@host:5432/db"
```

Generated Secret:
```yaml
data:
  LITELLM_MASTER_KEY: "xxx"
  DATABASE_URL: "postgresql://user:pass@host:5432/db"
```

Environment variable in pod:
```bash
DATABASE_URL="postgresql://user:pass@host:5432/db"
```

LiteLLM behavior: ✅ Connects to database successfully

---

### After Fix

**Scenario 1: No database URL provided**
```hcl
llmlite_database_url = ""
```

Generated Secret:
```yaml
data:
  LITELLM_MASTER_KEY: "xxx"
  # DATABASE_URL key is NOT present
```

Environment variable in pod:
```bash
# DATABASE_URL is NOT set at all
echo $DATABASE_URL  # Output: (empty line, variable doesn't exist)
```

LiteLLM behavior: ✅ Runs in no-database mode (correct!)

---

**Scenario 2: Database URL provided**
```hcl
llmlite_database_url = "postgresql://user:pass@host:5432/db"
```

Generated Secret:
```yaml
data:
  LITELLM_MASTER_KEY: "xxx"
  DATABASE_URL: "postgresql://user:pass@host:5432/db"
```

Environment variable in pod:
```bash
DATABASE_URL="postgresql://user:pass@host:5432/db"
```

LiteLLM behavior: ✅ Connects to database successfully

---

## Kubernetes `optional: true` Behavior

The deployment uses `secretKeyRef.optional: true`:

```yaml
env:
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: openclaw-llmlite
      key: DATABASE_URL
      optional: true  # ← Don't fail if key is missing
```

This means:
- If `DATABASE_URL` key exists in Secret → Set as environment variable
- If `DATABASE_URL` key doesn't exist → **Don't set the environment variable** (pod starts normally)

The key insight: **Not setting an env var is different from setting it to empty string!**

## Testing

### Test 1: No Database (Default)
```hcl
create_llmlite = true
# llmlite_database_url not set
```

Expected result:
```bash
kubectl exec -it deployment/openclaw-llmlite -- env | grep DATABASE_URL
# Output: (nothing - variable doesn't exist)

kubectl logs deployment/openclaw-llmlite | grep -i database
# Should NOT show database connection errors
```

### Test 2: With Database
```hcl
create_llmlite = true
llmlite_database_url = "postgresql://user:pass@postgres:5432/litellm"
```

Expected result:
```bash
kubectl exec -it deployment/openclaw-llmlite -- env | grep DATABASE_URL
# Output: DATABASE_URL=postgresql://user:pass@postgres:5432/litellm

kubectl logs deployment/openclaw-llmlite | grep -i database
# Should show successful database connection
```

## Files Changed

- `terraform/manifests.tf` - Fixed Secret data construction using `merge()`

## Benefits

1. ✅ **Correct LiteLLM behavior**: Runs in no-database mode when `DATABASE_URL` is not provided
2. ✅ **No breaking changes**: Existing deployments with `llmlite_database_url` set continue to work
3. ✅ **Cleaner configuration**: Secret only contains keys that have actual values
4. ✅ **Follows Kubernetes best practices**: Uses `optional: true` correctly

## Related

- Kubernetes docs: [secretKeyRef](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables)
- LiteLLM docs: [Database Configuration](https://docs.litellm.ai/docs/proxy/db)
