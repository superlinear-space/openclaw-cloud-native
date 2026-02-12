#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NAMESPACE="${OPENCLAW_NAMESPACE:-openclaw}"
IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    exit 1
  fi
}

require_cmd kubectl

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
  fi
}

update_secret_token() {
  local token="$1"
  local secret_yaml="apiVersion: v1
kind: Secret
metadata:
  name: openclaw-config
  namespace: $NAMESPACE
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: \"$token\""
  
  echo "$secret_yaml" | kubectl apply -f -
}

wait_for_pod() {
  local label="$1"
  echo "Waiting for pod with label $label to be ready..."
  kubectl wait --namespace="$NAMESPACE" \
    --for=condition=ready pod \
    -l "$label" \
    --timeout=300s
}

setup() {
  local token="${OPENCLAW_GATEWAY_TOKEN:-$(generate_token)}"
  
  cd "$REPO_ROOT"
  
  echo "==> Creating namespace and secrets..."
  kubectl apply -f "$REPO_ROOT/manifests/core/namespace.yaml"
  update_secret_token "$token"
  
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
  kubectl apply -f "$REPO_ROOT/manifests/core/config-pvc.yaml"
  kubectl apply -f "$REPO_ROOT/manifests/core/workspace-pvc.yaml"
  
  echo "==> Deploying gateway..."
  if [[ "$IMAGE" != "ghcr.io/openclaw/openclaw:latest" ]]; then
    kubectl set image deployment/openclaw-gateway gateway="$IMAGE" --namespace="$NAMESPACE"
  fi
  kubectl apply -f "$REPO_ROOT/manifests/core/gateway-deployment.yaml"
  kubectl apply -f "$REPO_ROOT/manifests/core/gateway-service.yaml"
  
  wait_for_pod "app=openclaw-gateway"
  
  echo ""
  echo "==> Onboarding (interactive)"
  echo "When prompted:"
  echo "  - Gateway bind: lan"
  echo "  - Gateway auth: token"
  echo "  - Gateway token: $token"
  echo "  - Tailscale exposure: Off"
  echo "  - Install Gateway daemon: No"
  echo ""
  
  run_cli onboard --no-install-daemon
  
  echo ""
  echo "==> Setup complete!"
  echo ""
  echo "Namespace: $NAMESPACE"
  echo "Token: $token"
  echo ""
  echo "Commands:"
  echo "  ./tools.sh status"
  echo "  ./tools.sh logs"
  echo ""
  echo "Provider setup:"
  echo "  ./tools.sh providers login"
  echo "  ./tools.sh providers add --provider telegram --token <token>"
}

run_cli() {
  local job_name="openclaw-cli-$(date +%s)"
  local node_selector_config=""
  if [[ -n "${OPENCLAW_NODE_SELECTOR:-}" ]]; then
    node_selector_config="      nodeSelector:
        ${OPENCLAW_NODE_SELECTOR}"
  fi
  local job_override
  job_override="apiVersion: batch/v1
kind: Job
metadata:
  name: $job_name
  namespace: $NAMESPACE
spec:
  template:
    metadata:
      name: openclaw-cli
    spec:
${node_selector_config}
      restartPolicy: Never
      containers:
      - name: cli
        image: $IMAGE
        env:
        - name: HOME
          value: /home/node
        - name: TERM
          value: xterm-256color
        stdin: true
        tty: true
        volumeMounts:
        - name: openclaw-config
          mountPath: /home/node/.openclaw
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
        command: [\"node\", \"dist/index.js\", \"$@\"]
      volumes:
      - name: openclaw-config
        persistentVolumeClaim:
          claimName: openclaw-config-pvc
      - name: openclaw-workspace
        persistentVolumeClaim:
          claimName: openclaw-workspace-pvc"
  
  local job_file
  job_file=$(mktemp)
  echo "$job_override" > "$job_file"
  
  kubectl apply -f "$job_file"
  
  echo "Waiting for CLI pod to be ready..."
  kubectl wait --namespace="$NAMESPACE" \
    --for=condition=ready pod \
    -l job-name="$job_name" \
    --timeout=60s 2>/dev/null || true
  
  local pod_name
  pod_name=$(kubectl get pods --namespace="$NAMESPACE" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [[ -n "$pod_name" ]]; then
    kubectl attach --namespace="$NAMESPACE" "$pod_name" -i
  fi
  
  kubectl delete job --namespace="$NAMESPACE" "$job_name" --ignore-not-found=true
  rm "$job_file"
}

status() {
  echo "==> OpenClaw Kubernetes Status"
  echo ""
  echo "Pods:"
  kubectl get pods --namespace="$NAMESPACE"
  echo ""
  echo "Services:"
  kubectl get svc --namespace="$NAMESPACE"
  echo ""
  echo "PVCs:"
  kubectl get pvc --namespace="$NAMESPACE"
}

logs() {
  kubectl logs -f --namespace="$NAMESPACE" openclaw-gateway
}

restart_gateway() {
  kubectl rollout restart deployment/openclaw-gateway --namespace="$NAMESPACE"
  wait_for_pod "app=openclaw-gateway"
  echo "Gateway restarted."
}

delete() {
  echo "==> WARNING: This will delete all OpenClaw resources"
  read -p "Are you sure? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace "$NAMESPACE"
    echo "Deleted namespace $NAMESPACE and all resources."
  fi
}

case "${1:-setup}" in
  setup)
    setup
    ;;
  cli)
    shift
    run_cli "$@"
    ;;
  providers)
    shift
    run_cli providers "$@"
    ;;
  status)
    status
    ;;
  logs)
    logs
    ;;
  restart)
    restart_gateway
    ;;
  delete)
    delete
    ;;
  *)
    echo "Usage: $0 {setup|cli|providers|status|logs|restart|delete}"
    echo ""
    echo "Commands:"
    echo "  setup          - Initial setup and onboarding"
    echo "  cli <args>     - Run OpenClaw CLI command"
    echo "  providers      - Run provider commands (shorthand for 'cli providers')"
    echo "  status         - Show deployment status"
    echo "  logs           - Follow gateway logs"
    echo "  restart        - Restart gateway deployment"
    echo "  delete         - Delete all OpenClaw resources"
    exit 1
    ;;
esac