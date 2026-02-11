# Read all Kubernetes YAML files as the source of truth
locals {
  namespace_yaml              = file("${path.module}/namespace.yaml")
  secrets_yaml                = file("${path.module}/secrets.yaml")
  config_pvc_yaml             = file("${path.module}/config-pvc.yaml")
  workspace_pvc_yaml          = file("${path.module}/workspace-pvc.yaml")
  gateway_deployment_yaml     = file("${path.module}/gateway-deployment.yaml")
  gateway_service_yaml        = file("${path.module}/gateway-service.yaml")
  onboarding_job_yaml         = file("${path.module}/onboarding-job.yaml")
  browserless_deployment_yaml = file("${path.module}/browserless-deployment.yaml")
  browserless_service_yaml    = file("${path.module}/browserless-service.yaml")
  searxng_deployment_yaml     = file("${path.module}/searxng-deployment.yaml")
  searxng_service_yaml        = file("${path.module}/searxng-service.yaml")
  searxng_pvc_yaml            = file("${path.module}/searxng-pvc.yaml")

  # Dynamic gateway token
  gateway_token = var.gateway_token != "" ? var.gateway_token : random_id.gateway_token.hex

  # Dynamic browserless token
  browserless_token = var.browserless_token != "" ? var.browserless_token : random_id.browserless_token.hex

  # Dynamic searxng secret
  searxng_secret = var.searxng_secret != "" ? var.searxng_secret : random_id.searxng_secret.hex
}

# Generate secrets manifest with data (base64-encoded) instead of stringData
locals {
  secrets_patched = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "openclaw-config"
      namespace = var.namespace
    }
    type = "Opaque"
    data = {
      OPENCLAW_GATEWAY_TOKEN = base64encode(local.gateway_token)
    }
  })
}

# Generate namespace manifest
locals {
  namespace_patched = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
    }
  })
}

# Generate PVC manifests
locals {
  config_pvc_patched = yamlencode(yamldecode(local.config_pvc_yaml))
}

locals {
  config_pvc_final = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.namespace}-config-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = var.config_storage_size
        }
      }
    }
  })
}

locals {
  workspace_pvc_final = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.namespace}-workspace-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = var.workspace_storage_size
        }
      }
    }
  })
}

# Generate storage config based on use_hostpath setting
locals {
  storage_config = var.use_hostpath ? {
    config_volume    = "        hostPath:\n          path: ${var.config_hostpath}\n          type: DirectoryOrCreate"
    workspace_volume = "        hostPath:\n          path: ${var.workspace_hostpath}\n          type: DirectoryOrCreate"
    } : {
    config_volume    = "        persistentVolumeClaim:\n          claimName: ${var.namespace}-config-pvc"
    workspace_volume = "        persistentVolumeClaim:\n          claimName: ${var.namespace}-workspace-pvc"
  }
}

# Generate init container YAML for fixing hostPath permissions
locals {
  fix_permissions_base = <<EOF
      - name: fix-permissions
        image: ${var.busybox_image}
        command: ["sh", "-c", "chown -R 1000:1000 /home/node/.openclaw && chmod -R 700 /home/node/.openclaw"]
        volumeMounts:
        - name: openclaw-config
          mountPath: /home/node/.openclaw
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
EOF

  fix_permissions_yaml = var.use_hostpath && var.fix_hostpath_permissions ? local.fix_permissions_base : ""
}

# Generate node selector YAML string from map
locals {
  node_selector_yaml_lines = [
    for k, v in var.node_selector : "        ${k}: \"${v}\""
  ]
  node_selector_yaml_str = join("\n", local.node_selector_yaml_lines)
}

# Patch gateway deployment with all variables (namespace LAST to avoid breaking PVC claim replacements)
locals {
  gateway_deployment_patched = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  local.gateway_deployment_yaml,
                  "image: ghcr.io/openclaw/openclaw:latest",
                  "image: ${var.container_image}"
                ),
                "image: busybox:latest",
                "image: ${var.busybox_image}"
              ),
              " --bind lan ",
              " --bind ${var.gateway_bind} "
            ),
            "--port\", \"18789",
            "--port\", \"${var.gateway_port}"
          ),
          "        - containerPort: 18789",
          "        - containerPort: ${var.gateway_port}"
        ),
        "        - containerPort: 18790",
        "        - containerPort: ${var.bridge_port}"
      ),
      "replicas: 1",
      "replicas: ${var.gateway_replicas}"
    ),
    "        openclaw-enabled: \"true\"",
    local.node_selector_yaml_str
  )

  gateway_deployment_port_fixed = local.gateway_deployment_patched
}

# Apply hostPath/PVC storage backend patch
locals {
  gateway_deployment_with_storage = replace(
    replace(
      local.gateway_deployment_port_fixed,
      "        persistentVolumeClaim:\n          claimName: openclaw-config-pvc",
      local.storage_config.config_volume
    ),
    "        persistentVolumeClaim:\n          claimName: openclaw-workspace-pvc",
    local.storage_config.workspace_volume
  )
}

# Conditionally insert fix-permissions init container in gateway deployment
locals {
  gateway_deployment_with_fix_permissions = var.use_hostpath && var.fix_hostpath_permissions ? replace(
    local.gateway_deployment_with_storage,
    "      initContainers:",
    "      initContainers:\n${local.fix_permissions_yaml}"
  ) : local.gateway_deployment_with_storage
}

# Generate additional hostPath volume YAML
locals {
  additional_volume_yaml = length(var.gateway_additional_hostpath_mounts) > 0 ? join("\n", [
    for m in var.gateway_additional_hostpath_mounts : <<EOF
      - name: ${m.name}
        hostPath:
          path: ${m.host_path}
          type: ${m.type}
EOF
  ]) : ""

  additional_volume_mount_yaml = length(var.gateway_additional_hostpath_mounts) > 0 ? join("\n", [
    for m in var.gateway_additional_hostpath_mounts : join("\n", compact([
      "        - name: ${m.name}",
      "          mountPath: ${m.mount_path}",
      m.read_only ? "          readOnly: true" : ""
    ]))
  ]) : ""
}

# Inject additional hostPath mounts into gateway deployment
locals {
  # First inject additional volumes (works for both PVC and hostPath modes)
  gateway_deployment_with_additional_volumes = length(var.gateway_additional_hostpath_mounts) > 0 ? (
    var.use_hostpath ? replace(
      local.gateway_deployment_with_fix_permissions,
      # hostPath mode: workspace volume uses hostPath
      "      - name: openclaw-workspace\n        hostPath:\n          path: ${var.workspace_hostpath}\n          type: DirectoryOrCreate",
      <<EOF
      - name: openclaw-workspace
        hostPath:
          path: ${var.workspace_hostpath}
          type: DirectoryOrCreate
${local.additional_volume_yaml}
EOF
    ) : replace(
      local.gateway_deployment_with_fix_permissions,
      # PVC mode: workspace volume uses persistentVolumeClaim
      "      - name: openclaw-workspace\n        persistentVolumeClaim:\n          claimName: ${var.namespace}-workspace-pvc",
      <<EOF
      - name: openclaw-workspace
        persistentVolumeClaim:
          claimName: ${var.namespace}-workspace-pvc
${local.additional_volume_yaml}
EOF
    )
  ) : local.gateway_deployment_with_fix_permissions

  # Then inject additional volume mounts
  gateway_deployment_with_additional_mounts = length(var.gateway_additional_hostpath_mounts) > 0 ? replace(
    local.gateway_deployment_with_additional_volumes,
    # Add additional volume mounts for gateway container only (using unique context from main container)
    "        - name: openclaw-workspace\n          mountPath: /home/node/.openclaw/workspace\n        command: [\"node\", \"dist/index.js\", \"gateway\",",
    <<EOF
        - name: openclaw-workspace
          mountPath: /home/node/.openclaw/workspace
${local.additional_volume_mount_yaml}
        command: ["node", "dist/index.js", "gateway",
EOF
  ) : local.gateway_deployment_with_additional_volumes
}

# Apply namespace LAST to avoid breaking PVC claim replacements
locals {
  gateway_deployment_final = replace(
    local.gateway_deployment_with_additional_mounts,
    "namespace: openclaw",
    "namespace: ${var.namespace}"
  )
}

# Patch onboarding job with all variables (namespace LAST to avoid breaking PVC claim replacements)
locals {
  onboarding_job_patched = replace(
    replace(
      replace(
        local.onboarding_job_yaml,
        "image: ghcr.io/openclaw/openclaw:latest",
        "image: ${var.container_image}"
      ),
      "image: busybox:1.36",
      "image: ${var.busybox_image}"
    ),
    "        openclaw-enabled: \"true\"",
    local.node_selector_yaml_str
  )
}

# Apply hostPath/PVC storage backend patch to onboarding job
locals {
  onboarding_job_with_storage = replace(
    replace(
      local.onboarding_job_patched,
      "        persistentVolumeClaim:\n          claimName: openclaw-config-pvc",
      local.storage_config.config_volume
    ),
    "        persistentVolumeClaim:\n          claimName: openclaw-workspace-pvc",
    local.storage_config.workspace_volume
  )
}

# Conditionally insert fix-permissions init container in onboarding job
locals {
  onboarding_job_with_fix_permissions = var.use_hostpath && var.fix_hostpath_permissions ? replace(
    local.onboarding_job_with_storage,
    "      initContainers:",
    "      initContainers:\n${local.fix_permissions_yaml}"
  ) : local.onboarding_job_with_storage
}

# Apply namespace LAST to avoid breaking PVC claim replacements
locals {
  onboarding_job_final = replace(
    local.onboarding_job_with_fix_permissions,
    "namespace: openclaw",
    "namespace: ${var.namespace}"
  )
}

# Generate service manifest
locals {
  gateway_service_patched = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "openclaw-gateway"
      namespace = var.namespace
    }
    spec = {
      type = var.service_type
      selector = {
        app = "openclaw-gateway"
      }
      ports = [
        {
          port       = var.gateway_port
          targetPort = var.gateway_port
          name       = "gateway"
        },
        {
          port       = var.bridge_port
          targetPort = var.bridge_port
          name       = "bridge"
        }
      ]
    }
  })
}

# Generate Claude secret if any keys are provided
locals {
  claude_secret_yaml = (var.claude_ai_session_key != "" || var.claude_web_session_key != "" || var.claude_web_cookie != "") ? yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "openclaw-claude"
      namespace = var.namespace
    }
    type = "Opaque"
    data = {
      CLAUDE_AI_SESSION_KEY  = var.claude_ai_session_key != "" ? base64encode(var.claude_ai_session_key) : ""
      CLAUDE_WEB_SESSION_KEY = var.claude_web_session_key != "" ? base64encode(var.claude_web_session_key) : ""
      CLAUDE_WEB_COOKIE      = var.claude_web_cookie != "" ? base64encode(var.claude_web_cookie) : ""
    }
  }) : null
}

# Patch browserless deployment with all variables (namespace LAST)
locals {
  browserless_deployment_patched = replace(
    replace(
      replace(
        replace(
          local.browserless_deployment_yaml,
          "image: ghcr.io/browserless/chromium:latest",
          "image: ${var.browserless_image}"
        ),
        "        - containerPort: 3000",
        "        - containerPort: ${var.browserless_port}"
      ),
      "replicas: 1",
      "replicas: ${var.browserless_replicas}"
    ),
    "        openclaw-enabled: \"true\"",
    local.node_selector_yaml_str
  )
}

# Apply shm size replacement
locals {
  browserless_deployment_with_shm = replace(
    local.browserless_deployment_patched,
    "sizeLimit: 1Gi",
    "sizeLimit: ${var.browserless_shm_size}"
  )
}

# Apply namespace LAST to avoid breaking other replacements
locals {
  browserless_deployment_final = replace(
    local.browserless_deployment_with_shm,
    "namespace: openclaw",
    "namespace: ${var.namespace}"
  )
}

# Generate browserless service manifest
locals {
  browserless_service_patched = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "openclaw-browserless"
      namespace = var.namespace
    }
    spec = {
      type = "ClusterIP"
      selector = {
        app = "openclaw-browserless"
      }
      ports = [
        {
          port       = var.browserless_port
          targetPort = var.browserless_port
          name       = "browserless"
        }
      ]
    }
  })
}

# SearXNG storage configuration (supports hostPath or PVC)
locals {
  searxng_storage_config = var.use_hostpath ? {
    config_volume = "        hostPath:\n          path: ${var.searxng_config_hostpath}\n          type: DirectoryOrCreate"
    data_volume   = "        hostPath:\n          path: ${var.searxng_data_hostpath}\n          type: DirectoryOrCreate"
    } : {
    config_volume = "        persistentVolumeClaim:\n          claimName: ${var.namespace}-searxng-config-pvc"
    data_volume   = "        persistentVolumeClaim:\n          claimName: ${var.namespace}-searxng-data-pvc"
  }
}

# Patch searxng deployment with all variables (namespace LAST)
locals {
  searxng_deployment_patched = replace(
    replace(
      replace(
        local.searxng_deployment_yaml,
        "image: docker.io/searxng/searxng:latest",
        "image: ${var.searxng_image}"
      ),
      "        - containerPort: 8080",
      "        - containerPort: ${var.searxng_port}"
    ),
    "replicas: 1",
    "replicas: ${var.searxng_replicas}"
  )
}

# Apply storage backend patch (hostPath or PVC)
locals {
  searxng_deployment_with_storage = replace(
    replace(
      local.searxng_deployment_patched,
      "        persistentVolumeClaim:\n          claimName: openclaw-searxng-config-pvc",
      local.searxng_storage_config.config_volume
    ),
    "        persistentVolumeClaim:\n          claimName: openclaw-searxng-data-pvc",
    local.searxng_storage_config.data_volume
  )
}

# Apply namespace LAST to avoid breaking other replacements
locals {
  searxng_deployment_final = replace(
    local.searxng_deployment_with_storage,
    "namespace: openclaw",
    "namespace: ${var.namespace}"
  )
}

# Generate searxng service manifest
locals {
  searxng_service_patched = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "openclaw-searxng"
      namespace = var.namespace
    }
    spec = {
      type = "ClusterIP"
      selector = {
        app = "openclaw-searxng"
      }
      ports = [
        {
          port       = var.searxng_port
          targetPort = var.searxng_port
          name       = "searxng"
        }
      ]
    }
  })
}

# Generate searxng PVC manifests (only used when use_hostpath=false)
locals {
  searxng_config_pvc = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.namespace}-searxng-config-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = var.searxng_config_storage_size
        }
      }
    }
  })

  searxng_data_pvc = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.namespace}-searxng-data-pvc"
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = var.searxng_data_storage_size
        }
      }
    }
  })
}
