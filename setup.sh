#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${OPENCLAW_NAMESPACE:-openclaw}"
IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"
BUSYBOX_IMAGE="${OPENCLAW_BUSYBOX_IMAGE:-busybox:latest}"
USE_HOSTPATH="${OPENCLAW_USE_HOSTPATH:-false}"
CONFIG_HOSTPATH="${OPENCLAW_CONFIG_HOSTPATH:-/var/lib/openclaw/config}"
WORKSPACE_HOSTPATH="${OPENCLAW_WORKSPACE_HOSTPATH:-/var/lib/openclaw/workspace}"
FIX_HOSTPATH_PERMISSIONS="${OPENCLAW_FIX_HOSTPATH_PERMISSIONS:-true}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    exit 1
  fi
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 <<'PY'
import secrets
print(secrets.token_hex(32))
PY
  fi
}

require_cmd kubectl

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'EOF'
OpenClaw Kubernetes Setup

This script automates deploying OpenClaw to Kubernetes.

Quick Start:
  export OPENCLAW_GATEWAY_TOKEN="<your-token>"
  ./setup.sh

Environment Variables:
    OPENCLAW_NAMESPACE      - Kubernetes namespace (default: openclaw)
    OPENCLAW_IMAGE          - Container image (default: ghcr.io/openclaw/openclaw:latest)
    OPENCLAW_BUSYBOX_IMAGE  - Busybox image for init containers (default: busybox:1.36)
    OPENCLAW_GATEWAY_TOKEN  - Gateway auth token (auto-generated if not set)
    OPENCLAW_USE_HOSTPATH   - Use hostPath instead of PVC (default: false)
    OPENCLAW_FIX_HOSTPATH_PERMISSIONS - Auto-fix hostPath permissions (default: true)
    OPENCLAW_CONFIG_HOSTPATH  - Host path for config (default: /var/lib/openclaw/config)
    OPENCLAW_WORKSPACE_HOSTPATH - Host path for workspace (default: /var/lib/openclaw/workspace)
    CLAUDE_AI_SESSION_KEY   - Optional: Claude AI key for AI features
    CLAUDE_WEB_SESSION_KEY  - Optional: Claude web session key
    CLAUDE_WEB_COOKIE       - Optional: Claude web cookie

 What it does:
   1. Creates Kubernetes namespace and secrets
   2. Creates PVCs (or uses hostPath if enabled) for config and workspace persistence
   3. Adds fix-permissions init container for hostPath (if enabled)
   4. Deploys gateway as a Deployment
   5. Creates LoadBalancer service to expose ports
   6. Runs interactive onboarding
   7. Provides provider setup commands

 After setup:
   - Gateway is running and accessible via LoadBalancer service
   - Config is persisted in PVCs (or host directories if hostPath enabled)
   - For hostPath: ownership set to uid 1000 and permissions to 700 automatically
   - Use ./tools.sh for common operations

EOF
      exit 0
      ;;
  esac
done

TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(generate_token)}"

echo "==> OpenClaw Kubernetes Setup"
echo ""
echo "Namespace: $NAMESPACE"
echo "Image: $IMAGE"
echo "Token: $TOKEN"
echo "Storage: $([[ "$USE_HOSTPATH" == "true" ]] && echo "hostPath ($CONFIG_HOSTPATH, $WORKSPACE_HOSTPATH)" || echo "PVC")"
echo ""

echo "==> Creating namespace..."
kubectl apply -f "$REPO_ROOT/namespace.yaml"

echo "==> Updating gateway token secret..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-config
  namespace: $NAMESPACE
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "$TOKEN"
EOF

if [[ -n "${CLAUDE_AI_SESSION_KEY:-}" ]]; then
   echo "==> Updating Claude secret..."
  kubectl create secret generic openclaw-claude \
    --namespace="$NAMESPACE" \
    --from-literal=CLAUDE_AI_SESSION_KEY="$CLAUDE_AI_SESSION_KEY" \
    --from-literal=CLAUDE_WEB_SESSION_KEY="${CLAUDE_WEB_SESSION_KEY:-}" \
    --from-literal=CLAUDE_WEB_COOKIE="${CLAUDE_WEB_COOKIE:-}" \
    --dry-run=client -o yaml | kubectl apply -f -
 fi

# Handle storage (PVC vs hostPath)
if [[ "$USE_HOSTPATH" == "true" ]]; then
   echo "==> Storage: Using hostPath ($CONFIG_HOSTPATH, $WORKSPACE_HOSTPATH)"
   # Create temporary hostPath-based manifests
   GATEWAY_PATCHED=$(mktemp)
   ONBOARDING_PATCHED=$(mktemp)
   sed "s|claimName: openclaw-config-pvc|path: $CONFIG_HOSTPATH\n        type: DirectoryOrCreate|; s|claimName: openclaw-workspace-pvc|path: $WORKSPACE_HOSTPATH\n        type: DirectoryOrCreate|; s|persistentVolumeClaim:|hostPath:|" "$REPO_ROOT/gateway-deployment.yaml" > "$GATEWAY_PATCHED"
   sed "s|claimName: openclaw-config-pvc|path: $CONFIG_HOSTPATH\n        type: DirectoryOrCreate|; s|claimName: openclaw-workspace-pvc|path: $WORKSPACE_HOSTPATH\n        type: DirectoryOrCreate|; s|persistentVolumeClaim:|hostPath:|" "$REPO_ROOT/onboarding-job.yaml" > "$ONBOARDING_PATCHED"
   
   # Add fix-permissions init container if enabled
   if [[ "$FIX_HOSTPATH_PERMISSIONS" == "true" ]]; then
     echo "==> Adding fix-permissions init container"
     python3 <<'PYTHON' "$GATEWAY_PATCHED" "$ONBOARDING_PATCHED"
import sys
gateway_path = sys.argv[1]
onboarding_path = sys.argv[2]

fix_perms = """      - name: fix-permissions
         image: $BUSYBOX_IMAGE
         command: ["sh", "-c", "chown -R 1000:1000 /home/node/.openclaw && chmod -R 700 /home/node/.openclaw"]
         volumeMounts:
         - name: openclaw-config
           mountPath: /home/node/.openclaw
         - name: openclaw-workspace
           mountPath: /home/node/.openclaw/workspace
         """

for path in [gateway_path, onboarding_path]:
    with open(path) as f:
        content = f.read()
    content = content.replace('      initContainers:', '      initContainers:\n' + fix_perms)
    with open(path, 'w') as f:
        f.write(content)
PYTHON
   fi
 else
   echo "==> Storage: Using PVCs"
   echo "==> Creating PVCs..."
   kubectl apply -f "$REPO_ROOT/config-pvc.yaml"
   kubectl apply -f "$REPO_ROOT/workspace-pvc.yaml"
   GATEWAY_PATCHED="$REPO_ROOT/gateway-deployment.yaml"
   ONBOARDING_PATCHED="$REPO_ROOT/onboarding-job.yaml"
 fi

echo ""
echo "==> Onboarding (interactive)"
echo "When prompted:"
echo "  - Gateway bind: lan"
echo "  - Gateway auth: token"
echo "  - Gateway token: $TOKEN"
echo "  - Tailscale exposure: Off"
echo "  - Install Gateway daemon: No"
echo ""

echo "==> Creating onboarding job..."
# Update namespace in onboarding job yaml
sed "s/namespace: openclaw/namespace: $NAMESPACE/" "$ONBOARDING_PATCHED" | kubectl apply -f -

echo "Attaching to onboarding pod..."
kubectl wait --namespace="$NAMESPACE" \
  --for=condition=ready pod \
  -l job-name=openclaw-onboarding \
  --timeout=60s 2>/dev/null || true

ONBOARD_POD=$(kubectl get pods --namespace="$NAMESPACE" -l job-name=openclaw-onboarding -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$ONBOARD_POD" ]]; then
  kubectl attach --namespace="$NAMESPACE" "$ONBOARD_POD" -c onboard -i
fi

echo "Cleaning up onboarding job..."
kubectl delete job --namespace="$NAMESPACE" openclaw-onboarding --ignore-not-found=true

echo ""
echo "==> Applying gateway deployment..."
# Update both namespace and image in the patched YAML
sed -e "s/namespace: openclaw/namespace: $NAMESPACE/" \
    -e "s|ghcr.io/openclaw/openclaw:latest|$IMAGE|" "$GATEWAY_PATCHED" | kubectl apply -f -
kubectl apply -f "$REPO_ROOT/gateway-service.yaml"

echo "==> Waiting for gateway pod to be ready..."
kubectl wait --namespace="$NAMESPACE" \
  --for=condition=ready pod \
  -l app=openclaw-gateway \
  --timeout=300s

echo ""
echo "==> Setup complete!"
echo ""
echo "Gateway is running with LoadBalancer service."
echo "Namespace: $NAMESPACE"
echo "Token: $TOKEN"
echo ""
echo "Next steps:"
echo "  - Check status: ./tools.sh status"
echo "  - View logs: ./tools.sh logs"
echo "  - Configure providers:"
echo ""
echo "    WhatsApp (QR):"
echo "      ./tools.sh providers login"
echo ""
echo "    Telegram (bot token):"
echo "      ./tools.sh providers add --provider telegram --token <token>"
echo ""
echo "    Discord (bot token):"
  echo "      ./tools.sh providers add --provider discord --token <token>"
  echo ""
  echo "Docs: https://docs.openclaw.ai/providers"

# Cleanup temporary files (for hostPath mode)
if [[ "$USE_HOSTPATH" == "true" && -n "${GATEWAY_PATCHED:-}" ]]; then
  rm -f "$GATEWAY_PATCHED" "$ONBOARDING_PATCHED" 2>/dev/null || true
fi