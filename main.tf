# Namespace
resource "kubernetes_namespace" "openclaw" {
  metadata {
    name = var.namespace
    labels = {
      app = "openclaw"
    }
  }
}

# Gateway Token Secret
resource "kubernetes_secret" "config" {
  metadata {
    name      = "openclaw-config"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  data = {
    OPENCLAW_GATEWAY_TOKEN = var.gateway_token != "" ? var.gateway_token : random_id.gateway_token.hex
  }

  type = "Opaque"
}

# Optional Claude Secret
resource "kubernetes_secret" "claude" {
  count = var.claude_ai_session_key != "" ? 1 : 0

  metadata {
    name      = "openclaw-claude"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  data = {
    CLAUDE_AI_SESSION_KEY  = var.claude_ai_session_key
    CLAUDE_WEB_SESSION_KEY = var.claude_web_session_key
    CLAUDE_WEB_COOKIE      = var.claude_web_cookie
  }

  type = "Opaque"
}

# Config PVC
resource "kubernetes_persistent_volume_claim" "config" {
  metadata {
    name      = "openclaw-config-pvc"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.config_storage_size
      }
    }
  }
}

# Workspace PVC
resource "kubernetes_persistent_volume_claim" "workspace" {
  metadata {
    name      = "openclaw-workspace-pvc"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.workspace_storage_size
      }
    }
  }
}

# Gateway Deployment
resource "kubernetes_deployment" "gateway" {
  metadata {
    name      = "openclaw-gateway"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
    labels = {
      app = "openclaw-gateway"
    }
  }

  spec {
    replicas = var.gateway_replicas

    selector {
      match_labels = {
        app = "openclaw-gateway"
      }
    }

    template {
      metadata {
        labels = {
          app = "openclaw-gateway"
        }
      }

      spec {
        node_selector = var.node_selector

        init_container {
          name    = "setup-directories"
          image   = "busybox:latest"
          command = ["sh", "-c", "mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace"]

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }
        }

        container {
          name  = "gateway"
          image = var.container_image

          env {
            name  = "HOME"
            value = "/home/node"
          }

          env {
            name  = "TERM"
            value = "xterm-256color"
          }

          env {
            name = "OPENCLAW_GATEWAY_TOKEN"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.config.metadata[0].name
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }

          env {
            name = "CLAUDE_AI_SESSION_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.claude[0].metadata[0].name
                key  = "CLAUDE_AI_SESSION_KEY"
              }
            }
          }

          env {
            name = "CLAUDE_WEB_SESSION_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.claude[0].metadata[0].name
                key  = "CLAUDE_WEB_SESSION_KEY"
              }
            }
          }

          env {
            name = "CLAUDE_WEB_COOKIE"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.claude[0].metadata[0].name
                key  = "CLAUDE_WEB_COOKIE"
              }
            }
          }

          port {
            container_port = 18789
            name           = "gateway"
          }

          port {
            container_port = 18790
            name           = "bridge"
          }

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }

          command = ["node", "dist/index.js", "gateway", "--bind", var.gateway_bind, "--port", "18789"]
        }

        volume {
          name = "openclaw-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.config.metadata[0].name
          }
        }

        volume {
          name = "openclaw-workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspace.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.config,
    kubernetes_secret.claude,
    kubernetes_persistent_volume_claim.config,
    kubernetes_persistent_volume_claim.workspace,
  ]
}

# Gateway Service
resource "kubernetes_service" "gateway" {
  metadata {
    name      = "openclaw-gateway"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  spec {
    selector = {
      app = "openclaw-gateway"
    }

    port {
      port        = var.gateway_port
      target_port = 18789
      name        = "gateway"
    }

    port {
      port        = var.bridge_port
      target_port = 18790
      name        = "bridge"
    }

    type = var.service_type
  }
}

# Onboarding Job
resource "kubernetes_job" "onboarding" {
  count = var.create_onboarding_job ? 1 : 0

  metadata {
    name      = "openclaw-onboarding"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "openclaw-onboarding"
      }

      spec {
        node_selector = var.node_selector

        init_container {
          name    = "setup-directories"
          image   = "busybox:latest"
          command = ["sh", "-c", "mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace"]

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }
        }

        container {
          name  = "onboard"
          image = var.container_image

          env {
            name  = "HOME"
            value = "/home/node"
          }

          env {
            name  = "TERM"
            value = "xterm-256color"
          }

          env {
            name = "OPENCLAW_GATEWAY_TOKEN"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.config.metadata[0].name
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }

          stdin = true
          tty   = true

          command = ["node", "dist/index.js", "onboard", "--no-install-daemon"]

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }
        }

        volume {
          name = "openclaw-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.config.metadata[0].name
          }
        }

        volume {
          name = "openclaw-workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspace.metadata[0].name
          }
        }

        restart_policy = "Never"
      }
    }

    backoff_limit = 0
  }

  depends_on = [
    kubernetes_deployment.gateway,
  ]
}

# CLI Job (for running commands)
resource "kubernetes_job" "cli" {
  for_each = var.cli_commands

  metadata {
    name      = "openclaw-cli-${each.key}"
    namespace = kubernetes_namespace.openclaw.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "openclaw-cli"
      }

      spec {
        node_selector = var.node_selector

        init_container {
          name    = "setup-directories"
          image   = "busybox:latest"
          command = ["sh", "-c", "mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace"]

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }
        }

        container {
          name  = "cli"
          image = var.container_image

          env {
            name  = "HOME"
            value = "/home/node"
          }

          env {
            name  = "TERM"
            value = "xterm-256color"
          }

          env {
            name = "OPENCLAW_GATEWAY_TOKEN"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.config.metadata[0].name
                key  = "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }

          stdin = true
          tty   = true

          command = ["node", "dist/index.js", "${each.value}"]

          volume_mount {
            name       = "openclaw-config"
            mount_path = "/home/node/.openclaw"
          }

          volume_mount {
            name       = "openclaw-workspace"
            mount_path = "/home/node/.openclaw/workspace"
          }
        }

        volume {
          name = "openclaw-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.config.metadata[0].name
          }
        }

        volume {
          name = "openclaw-workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspace.metadata[0].name
          }
        }

        restart_policy = "Never"
      }
    }

    backoff_limit = 0
  }

  depends_on = [
    kubernetes_deployment.gateway,
  ]
}