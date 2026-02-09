output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}

output "gateway_token" {
  description = "Gateway authentication token"
  value       = local.gateway_token
  sensitive   = true
}

output "gateway_service" {
  description = "Gateway service"
  value = var.create_gateway_deployment ? {
    name = "openclaw-gateway"
    type = var.service_type
  } : null
}

output "container_image" {
  description = "Container image being used"
  value       = var.create_gateway_deployment ? var.container_image : null
}

output "gateway_replicas" {
  description = "Number of gateway replicas"
  value       = var.create_gateway_deployment ? var.gateway_replicas : null
}

output "storage_backend" {
  description = "Storage backend being used"
  value       = var.use_hostpath ? "hostPath" : "PVC"
}

output "config_pvc" {
  description = "Config PVC name (null if using hostPath)"
  value       = var.use_hostpath ? null : "${var.namespace}-config-pvc"
}

output "workspace_pvc" {
  description = "Workspace PVC name (null if using hostPath)"
  value       = var.use_hostpath ? null : "${var.namespace}-workspace-pvc"
}

output "config_hostpath" {
  description = "Config hostPath (null if using PVC)"
  value       = var.use_hostpath ? var.config_hostpath : null
}

output "workspace_hostpath" {
  description = "Workspace hostPath (null if using PVC)"
  value       = var.use_hostpath ? var.workspace_hostpath : null
}

output "node_selector" {
  description = "Node selector being used"
  value       = var.node_selector
}

output "browserless_token" {
  description = "Browserless authentication token"
  value       = var.create_browserless ? local.browserless_token : null
  sensitive   = true
}

output "storage_config_info" {
  description = "Storage configuration information"
  value = {
    backend   = var.use_hostpath ? "hostPath" : "PVC"
    config    = var.use_hostpath ? var.config_hostpath : "${var.config_storage_size} PVC"
    workspace = var.use_hostpath ? var.workspace_hostpath : "${var.workspace_storage_size} PVC"
  }
}