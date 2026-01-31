resource "random_id" "gateway_token" {
  byte_length = 32
}

# Apply Kubernetes manifests using yamldecode
# YAML files are the single source of truth

resource "kubernetes_manifest" "namespace" {
  manifest = yamldecode(local.namespace_yaml)
}

resource "kubernetes_manifest" "secrets" {
  manifest   = yamldecode(local.patched_secrets_yaml)
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "config_pvc" {
  manifest   = yamldecode(local.config_pvc_yaml)
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "workspace_pvc" {
  manifest   = yamldecode(local.workspace_pvc_yaml)
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "gateway_deployment" {
  manifest = yamldecode(local.gateway_deployment_yaml)
  depends_on = [
    kubernetes_manifest.namespace,
    kubernetes_manifest.secrets,
    kubernetes_manifest.config_pvc,
    kubernetes_manifest.workspace_pvc,
  ]
}

resource "kubernetes_manifest" "gateway_service" {
  manifest   = yamldecode(local.gateway_service_yaml)
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "onboarding_job" {
  count      = var.create_onboarding_job ? 1 : 0
  manifest   = yamldecode(local.onboarding_job_yaml)
  depends_on = [kubernetes_manifest.gateway_deployment]
}