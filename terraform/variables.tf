variable "namespace" {
  description = "Kubernetes namespace for OpenClaw"
  type        = string
  default     = "openclaw"
}

variable "container_image" {
  description = "Container image for OpenClaw"
  type        = string
  default     = "ghcr.io/openclaw/openclaw:latest"
}

variable "busybox_image" {
  description = "Busybox image used for init containers"
  type        = string
  default     = "busybox:latest"
}

variable "gateway_token" {
  description = "Gateway authentication token (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "gateway_replicas" {
  description = "Number of gateway replicas"
  type        = number
  default     = 1
}

variable "gateway_bind" {
  description = "Gateway bind mode (lan, loopback, or public)"
  type        = string
  default     = "lan"
}

variable "gateway_port" {
  description = "Gateway service port"
  type        = number
  default     = 18789
}

variable "bridge_port" {
  description = "Bridge service port"
  type        = number
  default     = 18790
}

variable "service_type" {
  description = "Kubernetes service type (LoadBalancer, NodePort, ClusterIP)"
  type        = string
  default     = "LoadBalancer"
}

variable "config_storage_size" {
  description = "Storage size for config PVC"
  type        = string
  default     = "1Gi"
}

variable "workspace_storage_size" {
  description = "Storage size for workspace PVC"
  type        = string
  default     = "5Gi"
}

variable "use_hostpath" {
  description = "Use hostPath instead of PVC for storage (useful for development)"
  type        = bool
  default     = false
}

variable "fix_hostpath_permissions" {
  description = "Automatically fix hostPath permissions (chown 1000:1000, chmod 700)"
  type        = bool
  default     = true
}

variable "config_hostpath" {
  description = "Host path for config directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/config"
}

variable "workspace_hostpath" {
  description = "Host path for workspace directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/workspace"
}

variable "node_selector" {
  description = "Node selector labels for pod scheduling"
  type        = map(string)
  default = {
    "openclaw-enabled" = "true"
  }
}

variable "claude_ai_session_key" {
  description = "Claude AI session key (optional)"
  type        = string
  default     = ""
}

variable "claude_web_session_key" {
  description = "Claude web session key (optional)"
  type        = string
  default     = ""
}

variable "claude_web_cookie" {
  description = "Claude web cookie (optional)"
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "create_onboarding_job" {
  description = "Whether to create the onboarding job"
  type        = bool
  default     = false
}

variable "create_gateway_deployment" {
  description = "Whether to create the gateway deployment"
  type        = bool
  default     = true
}

variable "gateway_additional_hostpath_mounts" {
  description = "Additional hostPath mounts for gateway deployment"
  type = list(object({
    name       = string
    host_path  = string
    mount_path = string
    read_only  = optional(bool, false)
    type       = optional(string, "DirectoryOrCreate")
  }))
  default = []
}

variable "create_browserless" {
  description = "Whether to create the browserless deployment and service"
  type        = bool
  default     = false
}

variable "browserless_image" {
  description = "Container image for browserless"
  type        = string
  default     = "ghcr.io/browserless/chromium:latest"
}

variable "browserless_replicas" {
  description = "Number of browserless replicas"
  type        = number
  default     = 1
}

variable "browserless_port" {
  description = "Browserless service port"
  type        = number
  default     = 3000
}

variable "browserless_token" {
  description = "Browserless authentication token (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "browserless_shm_size" {
  description = "Size of shared memory (shm) for browserless (/dev/shm)"
  type        = string
  default     = "1Gi"
}

# SearXNG Variables
variable "create_searxng" {
  description = "Whether to create the SearXNG deployment and service"
  type        = bool
  default     = false
}

variable "searxng_image" {
  description = "Container image for SearXNG"
  type        = string
  default     = "docker.io/searxng/searxng:latest"
}

variable "searxng_replicas" {
  description = "Number of SearXNG replicas"
  type        = number
  default     = 1
}

variable "searxng_port" {
  description = "SearXNG service port"
  type        = number
  default     = 8080
}

variable "searxng_secret" {
  description = "SearXNG secret key (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "searxng_config_storage_size" {
  description = "Storage size for SearXNG config PVC"
  type        = string
  default     = "100Mi"
}

variable "searxng_data_storage_size" {
  description = "Storage size for SearXNG data PVC"
  type        = string
  default     = "500Mi"
}

variable "searxng_config_hostpath" {
  description = "Host path for SearXNG config directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/searxng/config"
}

variable "searxng_data_hostpath" {
  description = "Host path for SearXNG data directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/searxng/data"
}

# Qdrant Variables
variable "create_qdrant" {
  description = "Whether to create the Qdrant deployment and service"
  type        = bool
  default     = false
}

variable "qdrant_image" {
  description = "Container image for Qdrant"
  type        = string
  default     = "docker.io/qdrant/qdrant:latest"
}

variable "qdrant_replicas" {
  description = "Number of Qdrant replicas"
  type        = number
  default     = 1
}

variable "qdrant_http_port" {
  description = "Qdrant HTTP API port"
  type        = number
  default     = 6333
}

variable "qdrant_grpc_port" {
  description = "Qdrant gRPC port"
  type        = number
  default     = 6334
}

variable "qdrant_api_key" {
  description = "Qdrant API key for authentication (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "qdrant_config_storage_size" {
  description = "Storage size for Qdrant config PVC"
  type        = string
  default     = "100Mi"
}

variable "qdrant_storage_size" {
  description = "Storage size for Qdrant data PVC"
  type        = string
  default     = "5Gi"
}

variable "qdrant_config_hostpath" {
  description = "Host path for Qdrant config directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/qdrant/config"
}

variable "qdrant_storage_hostpath" {
  description = "Host path for Qdrant storage directory (required if use_hostpath=true)"
  type        = string
  default     = "/var/lib/openclaw/qdrant/storage"
}
