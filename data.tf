# Read all Kubernetes YAML files as the source of truth
locals {
  namespace_yaml          = file("${path.module}/namespace.yaml")
  secrets_yaml            = file("${path.module}/secrets.yaml")
  config_pvc_yaml         = file("${path.module}/config-pvc.yaml")
  workspace_pvc_yaml      = file("${path.module}/workspace-pvc.yaml")
  gateway_deployment_yaml = file("${path.module}/gateway-deployment.yaml")
  gateway_service_yaml    = file("${path.module}/gateway-service.yaml")
  onboarding_job_yaml     = file("${path.module}/onboarding-job.yaml")

  # Dynamic gateway token
  gateway_token = var.gateway_token != "" ? var.gateway_token : random_id.gateway_token.hex
}

# Generate patched secrets with the token
locals {
  patched_secrets_yaml = replace(
    local.secrets_yaml,
    "replace-with-generated-token",
    local.gateway_token
  )
}