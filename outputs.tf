variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.openclaw.metadata[0].name
}

output "gateway_token" {
  description = "Gateway authentication token"
  value       = kubernetes_secret.config.data["OPENCLAW_GATEWAY_TOKEN"]
  sensitive   = true
}

output "gateway_service" {
  description = "Gateway service"
  value = {
    name = kubernetes_service.gateway.metadata[0].name
    type = kubernetes_service.gateway.spec[0].type
  }
}

output "onboarding_token" {
  description = "Token to use for onboarding"
  value = var.create_onboarding_job ? (
    var.onboarding_token != "" ? var.onboarding_token : random_id.gateway_token.hex
  ) : null
}

output "config_pvc" {
  description = "Config PVC name"
  value       = kubernetes_persistent_volume_claim.config.metadata[0].name
}

output "workspace_pvc" {
  description = "Workspace PVC name"
  value       = kubernetes_persistent_volume_claim.workspace.metadata[0].name
}