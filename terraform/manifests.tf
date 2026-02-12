resource "random_id" "gateway_token" {
  byte_length = 32
}

resource "random_id" "browserless_token" {
  byte_length = 32
}

resource "random_id" "searxng_secret" {
  byte_length = 32
}

resource "random_id" "qdrant_api_key" {
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

# Browserless Secret - use dedicated resource for browserless token
resource "kubernetes_secret" "openclaw_browserless" {
  metadata {
    name      = "openclaw-browserless"
    namespace = var.namespace
    labels = {
      app = "openclaw"
    }
  }

  type = "Opaque"
  data = {
    BROWSERLESS_TOKEN = local.browserless_token
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

resource "kubernetes_manifest" "browserless_deployment" {
  count    = var.create_browserless ? 1 : 0
  manifest = yamldecode(local.browserless_deployment_final)
}

resource "kubernetes_manifest" "browserless_service" {
  count    = var.create_browserless ? 1 : 0
  manifest = yamldecode(local.browserless_service_patched)
}

# SearXNG Secret
resource "kubernetes_secret" "openclaw_searxng" {
  count = var.create_searxng ? 1 : 0

  metadata {
    name      = "openclaw-searxng"
    namespace = var.namespace
    labels = {
      app = "openclaw"
    }
  }

  type = "Opaque"
  data = {
    SEARXNG_SECRET = local.searxng_secret
  }
}

# SearXNG PVCs (only created when not using hostPath)
resource "kubernetes_manifest" "searxng_config_pvc" {
  count    = var.create_searxng && !var.use_hostpath ? 1 : 0
  manifest = yamldecode(local.searxng_config_pvc)
}

resource "kubernetes_manifest" "searxng_data_pvc" {
  count    = var.create_searxng && !var.use_hostpath ? 1 : 0
  manifest = yamldecode(local.searxng_data_pvc)
}

resource "kubernetes_manifest" "searxng_deployment" {
  count    = var.create_searxng ? 1 : 0
  manifest = yamldecode(local.searxng_deployment_final)
}

resource "kubernetes_manifest" "searxng_service" {
  count    = var.create_searxng ? 1 : 0
  manifest = yamldecode(local.searxng_service_patched)
}

# Qdrant Secret
resource "kubernetes_secret" "openclaw_qdrant" {
  count = var.create_qdrant ? 1 : 0

  metadata {
    name      = "openclaw-qdrant"
    namespace = var.namespace
    labels = {
      app = "openclaw"
    }
  }

  type = "Opaque"
  data = {
    QDRANT_API_KEY = local.qdrant_api_key
  }
}

# Qdrant PVCs (only created when not using hostPath)
resource "kubernetes_manifest" "qdrant_config_pvc" {
  count    = var.create_qdrant && !var.use_hostpath ? 1 : 0
  manifest = yamldecode(local.qdrant_config_pvc)
}

resource "kubernetes_manifest" "qdrant_storage_pvc" {
  count    = var.create_qdrant && !var.use_hostpath ? 1 : 0
  manifest = yamldecode(local.qdrant_storage_pvc)
}

resource "kubernetes_manifest" "qdrant_deployment" {
  count    = var.create_qdrant ? 1 : 0
  manifest = yamldecode(local.qdrant_deployment_final)
}

resource "kubernetes_manifest" "qdrant_service" {
  count    = var.create_qdrant ? 1 : 0
  manifest = yamldecode(local.qdrant_service_patched)
}
