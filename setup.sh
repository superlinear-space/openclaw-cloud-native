#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${OPENCLAW_NAMESPACE:-openclaw}"
IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

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
  OPENCLAW_GATEWAY_TOKEN  - Gateway auth token (auto-generated if not set)
  CLAUDE_AI_SESSION_KEY   - Optional: Claude AI key for AI features
  CLAUDE_WEB_SESSION_KEY  - Optional: Claude web session key
  CLAUDE_WEB_COOKIE       - Optional: Claude web cookie

What it does:
  1. Creates Kubernetes namespace and secrets
  2. Creates PVCs for config and workspace persistence
  3. Deploys gateway as a Deployment
  4. Creates LoadBalancer service to expose ports
  5. Runs interactive onboarding
  6. Provides provider setup commands

After setup:
  - Gateway is running and accessible via LoadBalancer service
  - Config is persisted in PVCs
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

echo "==> Creating PVCs..."
kubectl apply -f "$REPO_ROOT/config-pvc.yaml"
kubectl apply -f "$REPO_ROOT/workspace-pvc.yaml"

echo "==> Applying gateway deployment..."
if [[ "$IMAGE" != "ghcr.io/openclaw/openclaw:latest" ]]; then
  kubectl set image deployment/openclaw-gateway gateway="$IMAGE" --namespace="$NAMESPACE"
fi
kubectl apply -f "$REPO_ROOT/gateway-deployment.yaml"
kubectl apply -f "$REPO_ROOT/gateway-service.yaml"

echo "==> Waiting for gateway pod to be ready..."
kubectl wait --namespace="$NAMESPACE" \
  --for=condition=ready pod \
  -l app=openclaw-gateway \
  --timeout=300s

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
local node_selector_config=""
if [[ -n "${OPENCLAW_NODE_SELECTOR:-}" ]]; then
  node_selector_config="        nodeSelector:
          ${OPENCLAW_NODE_SELECTOR}"
fi
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: openclaw-onboarding
  namespace: $NAMESPACE
spec:
  template:
    metadata:
      name: openclaw-onboarding
    spec:
${node_selector_config}
      initContainers:
      - name: setup-directories
        image: busybox:latest
        command: ["sh", "-c", "mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace"]
        volumeMounts:
        - name: openclaw-config
          mountPath: /home/node/.openclaw
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
      containers:
      - name: onboard
        image: $IMAGE
        env:
        - name: HOME
          value: /home/node
        - name: TERM
          value: xterm-256color
        - name: OPENCLAW_GATEWAY_TOKEN
          valueFrom:
            secretKeyRef:
              name: openclaw-config
              key: OPENCLAW_GATEWAY_TOKEN
        stdin: true
        tty: true
        volumeMounts:
        - name: openclaw-config
          mountPath: /home/node/.openclaw
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
        command: ["node", "dist/index.js", "onboard", "--no-install-daemon"]
      volumes:
      - name: openclaw-config
        persistentVolumeClaim:
          claimName: openclaw-config-pvc
      - name: openclaw-workspace
        persistentVolumeClaim:
          claimName: openclaw-workspace-pvc
EOF

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