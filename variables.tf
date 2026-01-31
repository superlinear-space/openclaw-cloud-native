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

variable "cli_commands" {
  description = "Map of CLI commands to run as jobs (format: {\"name\" = \"command\"})"
  type        = map(string)
  default     = {}
}

variable "create_onboarding_job" {
  description = "Whether to create the onboarding job"
  type        = bool
  default     = false
}

variable "onboarding_token" {
  description = "Token to use for onboarding (will be generated if empty)"
  type        = string
  default     = ""
}