#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "OpenClaw Kubernetes - Generate Single Manifest"
echo "=============================================="
echo ""

# Parse arguments
NAMESPACE="${1:-openclaw}"
TOKEN="${2:-$(openssl rand -hex 32)}"
IMAGE="${3:-ghcr.io/openclaw/openclaw:latest}"
REPLICAS="${4:-1}"
SERVICE_TYPE="${5:-LoadBalancer}"
CONFIG_SIZE="${6:-1Gi}"
WORKSPACE_SIZE="${7:-5Gi}"

cat > "$REPO_ROOT/manifests/bundled/openclaw-k8s.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
  labels:
    app: openclaw

---
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-config
  namespace: $NAMESPACE
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "$TOKEN"

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-config-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $CONFIG_SIZE

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-workspace-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $WORKSPACE_SIZE

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw-gateway
  namespace: $NAMESPACE
  labels:
    app: openclaw-gateway
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: openclaw-gateway
  template:
    metadata:
      labels:
        app: openclaw-gateway
    spec:
      nodeSelector:
        openclaw-enabled: "true"
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
      - name: gateway
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
        ports:
        - containerPort: 18789
          name: gateway
        - containerPort: 18790
          name: bridge
        volumeMounts:
        - name: openclaw-config
          mountPath: /home/node/.openclaw
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
        command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
      volumes:
      - name: openclaw-config
        persistentVolumeClaim:
          claimName: openclaw-config-pvc
      - name: openclaw-workspace
        persistentVolumeClaim:
          claimName: openclaw-workspace-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: openclaw-gateway
  namespace: $NAMESPACE
spec:
  selector:
    app: openclaw-gateway
  ports:
  - port: 18789
    targetPort: 18789
    name: gateway
  - port: 18790
    targetPort: 18790
    name: bridge
  type: $SERVICE_TYPE

---
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
      nodeSelector:
        openclaw-enabled: "true"
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
      restartPolicy: Never
  backoffLimit: 0
EOF

echo "Generated manifests/bundled/openclaw-k8s.yaml"
echo ""
echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Token: $TOKEN"
echo "  Image: $IMAGE"
echo "  Replicas: $REPLICAS"
echo "  Service Type: $SERVICE_TYPE"
echo "  Config Storage: $CONFIG_SIZE"
echo "  Workspace Storage: $WORKSPACE_SIZE"
echo ""
echo "Apply with:"
echo "  kubectl apply -f manifests/bundled/openclaw-k8s.yaml"
echo ""
echo "Or use Terraform with:"
echo "  cd terraform && terraform init && terraform apply"