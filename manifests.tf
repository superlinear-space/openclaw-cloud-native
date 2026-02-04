resource "random_id" "gateway_token" {
  byte_length = 32
}

# Use dedicated kubernetes_secret for Secret (better provider support)
resource "kubernetes_secret" "openclaw_config" {
  metadata {
    name      = "openclaw-config"
    namespace = var.namespace
    labels = {
      app = "openclaw"
    }
  }

  type = "Opaque"
  data = {
    OPENCLAW_GATEWAY_TOKEN = local.gateway_token
  }
}

# Claude Secret - use dedicated resource if Claude keys are provided
resource "kubernetes_secret" "openclaw_claude" {
  count = (var.claude_ai_session_key != "" || var.claude_web_session_key != "" || var.claude_web_cookie != "") ? 1 : 0

  metadata {
    name      = "openclaw-claude"
    namespace = var.namespace
    labels = {
      app = "openclaw"
    }
  }

  type = "Opaque"
  data = {
    CLAUDE_AI_SESSION_KEY  = var.claude_ai_session_key
    CLAUDE_WEB_SESSION_KEY = var.claude_web_session_key
    CLAUDE_WEB_COOKIE      = var.claude_web_cookie
  }
}

# Use kubernetes_manifest for other standard resources (no dedicated resources yet)
resource "kubernetes_manifest" "namespace" {
  manifest = yamldecode(local.namespace_patched)
}

resource "kubernetes_manifest" "config_pvc" {
  count    = var.use_hostpath ? 0 : 1
  manifest = yamldecode(local.config_pvc_final)
}

resource "kubernetes_manifest" "workspace_pvc" {
  count    = var.use_hostpath ? 0 : 1
  manifest = yamldecode(local.workspace_pvc_final)
}

resource "kubernetes_manifest" "onboarding_job" {
  count    = var.create_onboarding_job ? 1 : 0
  manifest = yamldecode(local.onboarding_job_final)
}

# IMPORTANT: There is no automatic ordering guarantee between onboarding_job and gateway_deployment
# For initial setup, use sequential applies with create_gateway_deployment=false
# Recommended workflow:
# 1. terraform apply -var="create_onboarding_job=true" -var="create_gateway_deployment=false"
# 2. kubectl attach -n <namespace> openclaw-onboarding -i -c onboard  # Wait for completion
# 3. kubectl delete job -n <namespace> openclaw-onboarding  # Clean up (optional, job will self-terminate)
# 4. terraform apply -var="create_onboarding_job=false" -var="create_gateway_deployment=true"  # Gateway now starts with initialized config
resource "kubernetes_manifest" "gateway_deployment" {
  count    = var.create_gateway_deployment ? 1 : 0
  manifest = yamldecode(local.gateway_deployment_final)
}

resource "kubernetes_manifest" "gateway_service" {
  count    = var.create_gateway_deployment ? 1 : 0
  manifest = yamldecode(local.gateway_service_patched)
}