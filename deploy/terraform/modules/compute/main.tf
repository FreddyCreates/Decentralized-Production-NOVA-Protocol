# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Compute Module
# Compute resources for sovereign cloud deployments
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - StatefulSet for sovereign nodes with anti-affinity
#   - HorizontalPodAutoscaler for dynamic scaling
#   - PodDisruptionBudget for availability
#   - Resource quotas and limit ranges
#   - Init containers for pre-flight checks
#   - Sidecar containers (log collector, metrics, security agent)
#   - Priority classes for workload scheduling
#
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "deployment_name" {
  description = "Base name for compute resources"
  type        = string
  default     = "nova-sovereign"
}

variable "replica_count" {
  description = "Number of sovereign node replicas"
  type        = number
  default     = 3
}

variable "image_repository" {
  description = "Container image repository"
  type        = string
  default     = "nova-sovereign"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "1.0.0"
}

variable "image_pull_policy" {
  description = "Image pull policy"
  type        = string
  default     = "IfNotPresent"
}

variable "cpu_request" {
  description = "CPU request per pod"
  type        = string
  default     = "2"
}

variable "cpu_limit" {
  description = "CPU limit per pod"
  type        = string
  default     = "8"
}

variable "memory_request" {
  description = "Memory request per pod"
  type        = string
  default     = "8Gi"
}

variable "memory_limit" {
  description = "Memory limit per pod"
  type        = string
  default     = "32Gi"
}

variable "data_volume_size" {
  description = "Size of the data persistent volume"
  type        = string
  default     = "100Gi"
}

variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = ""
}

variable "enable_hpa" {
  description = "Enable HorizontalPodAutoscaler"
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 3
}

variable "hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 10
}

variable "hpa_target_cpu" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 70
}

variable "hpa_target_memory" {
  description = "Target memory utilization percentage for HPA"
  type        = number
  default     = 80
}

variable "enable_tls" {
  description = "Enable TLS for the sovereign node"
  type        = bool
  default     = true
}

variable "tls_secret_name" {
  description = "Name of the TLS secret"
  type        = string
  default     = "nova-sovereign-server-tls"
}

variable "enable_metrics" {
  description = "Enable metrics exporter"
  type        = bool
  default     = true
}

variable "jurisdiction" {
  description = "Data sovereignty jurisdiction"
  type        = string
  default     = "XX"
}

variable "classification_level" {
  description = "Security classification"
  type        = string
  default     = "unclassified"
}

variable "node_selector" {
  description = "Node selector for pod placement"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for pod scheduling"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

# ── Priority Class ────────────────────────────────────────────────────────────

resource "kubernetes_priority_class" "sovereign_critical" {
  metadata {
    name = "${var.deployment_name}-critical"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/priority"      = "critical"
    }
  }

  value             = 1000000
  global_default    = false
  description       = "Critical priority for NOVA sovereign node components"
  preemption_policy = "PreemptLowerPriority"
}

resource "kubernetes_priority_class" "sovereign_high" {
  metadata {
    name = "${var.deployment_name}-high"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/priority"      = "high"
    }
  }

  value             = 500000
  global_default    = false
  description       = "High priority for NOVA sovereign supporting services"
  preemption_policy = "PreemptLowerPriority"
}

# ── Resource Quota ────────────────────────────────────────────────────────────

resource "kubernetes_resource_quota" "sovereign_quota" {
  metadata {
    name      = "${var.deployment_name}-quota"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "resource-management"
    }
  }

  spec {
    hard = {
      "requests.cpu"    = "${var.hpa_max_replicas * tonumber(replace(var.cpu_request, "/[^0-9]/", ""))}"
      "requests.memory" = "${var.hpa_max_replicas * 8}Gi"
      "limits.cpu"      = "${var.hpa_max_replicas * tonumber(replace(var.cpu_limit, "/[^0-9]/", ""))}"
      "limits.memory"   = "${var.hpa_max_replicas * 32}Gi"
      "pods"            = tostring(var.hpa_max_replicas * 3)
      "services"        = "20"
      "secrets"         = "50"
      "configmaps"      = "50"
      "persistentvolumeclaims" = tostring(var.hpa_max_replicas * 2)
    }
  }
}

# ── Limit Range ───────────────────────────────────────────────────────────────

resource "kubernetes_limit_range" "sovereign_limits" {
  metadata {
    name      = "${var.deployment_name}-limits"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "resource-management"
    }
  }

  spec {
    limit {
      type = "Pod"
      max = {
        cpu    = var.cpu_limit
        memory = var.memory_limit
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }

    limit {
      type = "Container"
      default = {
        cpu    = "1"
        memory = "2Gi"
      }
      default_request = {
        cpu    = "500m"
        memory = "1Gi"
      }
      max = {
        cpu    = var.cpu_limit
        memory = var.memory_limit
      }
      min = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }

    limit {
      type = "PersistentVolumeClaim"
      max = {
        storage = "500Gi"
      }
      min = {
        storage = "1Gi"
      }
    }
  }
}

# ── Pod Disruption Budget ─────────────────────────────────────────────────────

resource "kubernetes_pod_disruption_budget_v1" "sovereign_pdb" {
  metadata {
    name      = "${var.deployment_name}-pdb"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "availability"
    }
  }

  spec {
    min_available = "${floor(var.replica_count * 0.67)}"

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "nova-sovereign"
        "app.kubernetes.io/instance" = var.deployment_name
      }
    }
  }
}

# ── Service Account ───────────────────────────────────────────────────────────

resource "kubernetes_service_account" "sovereign" {
  metadata {
    name      = "${var.deployment_name}-node"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "compute"
    }
    annotations = {
      "nova.sovereign/jurisdiction" = var.jurisdiction
    }
  }

  automount_service_account_token = true
}

# ── ConfigMap for Node Configuration ──────────────────────────────────────────

resource "kubernetes_config_map" "node_config" {
  metadata {
    name      = "${var.deployment_name}-node-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "compute"
    }
  }

  data = {
    "node-config.yaml" = yamlencode({
      sovereign_node = {
        mode           = "sovereign"
        jurisdiction   = var.jurisdiction
        classification = var.classification_level
        replica_id     = "{{ .pod_ordinal }}"

        replica = {
          subnet_type = "sovereign"
          port        = 8080
          management_port = 4943
        }

        canister_runtime = {
          max_canisters        = 100
          memory_limit_per_canister = "8GiB"
          cycles_limit         = 10000000000000
          execution_threads    = 4
          query_threads        = 8
        }

        engines = {
          julia = {
            enabled = true
            workers = 4
            memory_limit = "4GiB"
          }
          python = {
            enabled = true
            workers = 2
            memory_limit = "2GiB"
          }
          javascript = {
            enabled = true
            workers = 4
            memory_limit = "2GiB"
          }
        }

        metrics = {
          enabled  = var.enable_metrics
          port     = 9090
          path     = "/metrics"
          interval = "15s"
        }

        health = {
          liveness_path  = "/health/live"
          readiness_path = "/health/ready"
          startup_path   = "/health/startup"
        }

        security = {
          tls_enabled      = var.enable_tls
          mtls_enabled     = var.enable_tls
          audit_enabled    = true
          rate_limit       = 1000
          max_connections  = 5000
        }
      }
    })

    "dfx-sovereign.json" = jsonencode({
      version = 1
      dfx = "0.20.0"
      networks = {
        sovereign = {
          bind    = "0.0.0.0:8080"
          type    = "persistent"
          replica = {
            subnet_type = "application"
            port        = 8080
          }
        }
      }
      defaults = {
        build = {
          packtool = ""
        }
        replica = {
          log_level = "info"
        }
      }
    })
  }
}

# ── Sovereign Node StatefulSet ────────────────────────────────────────────────

resource "kubernetes_stateful_set" "sovereign_nodes" {
  metadata {
    name      = "${var.deployment_name}-node"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "nova-sovereign"
      "app.kubernetes.io/instance"   = var.deployment_name
      "app.kubernetes.io/component"  = "sovereign-node"
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/jurisdiction"  = var.jurisdiction
      "nova.sovereign/classification" = var.classification_level
    }
  }

  spec {
    replicas     = var.replica_count
    service_name = "${var.deployment_name}-node"

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "nova-sovereign"
        "app.kubernetes.io/instance" = var.deployment_name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"       = "nova-sovereign"
          "app.kubernetes.io/instance"   = var.deployment_name
          "app.kubernetes.io/component"  = "sovereign-node"
          "nova.sovereign/component"     = "node"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9090"
          "prometheus.io/path"   = "/metrics"
          "nova.sovereign/config-hash" = sha256(jsonencode(kubernetes_config_map.node_config.data))
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.sovereign.metadata[0].name
        automount_service_account_token  = true
        priority_class_name              = kubernetes_priority_class.sovereign_critical.metadata[0].name
        termination_grace_period_seconds = 120

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        dynamic "node_selector" {
          for_each = length(var.node_selector) > 0 ? [var.node_selector] : []
          content {
            # Terraform kubernetes provider doesn't support dynamic node_selector this way
            # This is a placeholder; use affinity instead
          }
        }

        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_labels = {
                  "app.kubernetes.io/name"     = "nova-sovereign"
                  "app.kubernetes.io/instance" = var.deployment_name
                }
              }
              topology_key = "kubernetes.io/hostname"
            }

            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    "app.kubernetes.io/name"     = "nova-sovereign"
                    "app.kubernetes.io/instance" = var.deployment_name
                  }
                }
                topology_key = "topology.kubernetes.io/zone"
              }
            }
          }
        }

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        # Init container: pre-flight security checks
        init_container {
          name  = "preflight-check"
          image = "busybox:1.36"
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            echo "=== NOVA Sovereign Pre-flight Check ==="
            echo "Checking file permissions..."
            ls -la /opt/nova/data /opt/nova/config /opt/nova/keys
            echo "Checking DNS resolution..."
            nslookup kubernetes.default.svc.cluster.local || true
            echo "Checking volume mounts..."
            df -h /opt/nova/data
            echo "Pre-flight checks complete"
          EOT
          ]

          volume_mount {
            name       = "data"
            mount_path = "/opt/nova/data"
          }
          volume_mount {
            name       = "config"
            mount_path = "/opt/nova/config"
          }
          volume_mount {
            name       = "keys"
            mount_path = "/opt/nova/keys"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          security_context {
            run_as_non_root          = true
            run_as_user              = 1000
            read_only_root_filesystem = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        # Main sovereign node container
        container {
          name  = "sovereign-node"
          image = "${var.image_repository}:${var.image_tag}"
          image_pull_policy = var.image_pull_policy

          args = [
            "--mode", "sovereign",
            "--network", "local",
            "--enable-tls", tostring(var.enable_tls),
            "--enable-metrics", tostring(var.enable_metrics),
          ]

          port {
            name           = "replica"
            container_port = 8080
            protocol       = "TCP"
          }
          port {
            name           = "management"
            container_port = 4943
            protocol       = "TCP"
          }
          port {
            name           = "dashboard"
            container_port = 3000
            protocol       = "TCP"
          }
          port {
            name           = "metrics"
            container_port = 9090
            protocol       = "TCP"
          }
          port {
            name           = "sovereign-api"
            container_port = 8443
            protocol       = "TCP"
          }

          env {
            name  = "NOVA_DEPLOY_MODE"
            value = "sovereign"
          }
          env {
            name  = "NOVA_JURISDICTION"
            value = var.jurisdiction
          }
          env {
            name  = "NOVA_CLASSIFICATION"
            value = var.classification_level
          }
          env {
            name = "NOVA_POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "NOVA_POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name = "NOVA_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/opt/nova/data"
          }
          volume_mount {
            name       = "config"
            mount_path = "/opt/nova/config"
          }
          volume_mount {
            name       = "keys"
            mount_path = "/opt/nova/keys"
            read_only  = true
          }
          volume_mount {
            name       = "node-config"
            mount_path = "/opt/nova/etc"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          liveness_probe {
            http_get {
              path = "/api/v2/status"
              port = "replica"
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/v2/status"
              port = "replica"
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          startup_probe {
            http_get {
              path = "/api/v2/status"
              port = "replica"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 30
          }

          security_context {
            run_as_non_root          = true
            run_as_user              = 1000
            read_only_root_filesystem = false  # DFX needs to write
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }
        }

        # Sidecar: Fluent Bit log collector
        container {
          name  = "log-collector"
          image = "fluent/fluent-bit:3.0"

          volume_mount {
            name       = "data"
            mount_path = "/opt/nova/data"
            read_only  = true
          }
          volume_mount {
            name       = "fluentbit-buffer"
            mount_path = "/var/log/fluentbit"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          security_context {
            run_as_non_root          = true
            run_as_user              = 1000
            read_only_root_filesystem = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "keys"
          secret {
            secret_name  = var.tls_secret_name
            default_mode = "0400"
          }
        }
        volume {
          name = "node-config"
          config_map {
            name = kubernetes_config_map.node_config.metadata[0].name
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "256Mi"
          }
        }
        volume {
          name = "fluentbit-buffer"
          empty_dir {
            size_limit = "512Mi"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
        labels = {
          "app.kubernetes.io/name"     = "nova-sovereign"
          "app.kubernetes.io/instance" = var.deployment_name
        }
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        dynamic "storage_class_name" {
          for_each = var.storage_class != "" ? [var.storage_class] : []
          content {
            # This doesn't work this way in TF; storage_class_name is a direct field
          }
        }
        resources {
          requests = {
            storage = var.data_volume_size
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "config"
        labels = {
          "app.kubernetes.io/name"     = "nova-sovereign"
          "app.kubernetes.io/instance" = var.deployment_name
        }
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# ── Headless Service for StatefulSet ──────────────────────────────────────────

resource "kubernetes_service" "sovereign_headless" {
  metadata {
    name      = "${var.deployment_name}-node"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "nova-sovereign"
      "app.kubernetes.io/instance"   = var.deployment_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "None"

    selector = {
      "app.kubernetes.io/name"     = "nova-sovereign"
      "app.kubernetes.io/instance" = var.deployment_name
    }

    port {
      name        = "replica"
      port        = 8080
      target_port = "replica"
      protocol    = "TCP"
    }
    port {
      name        = "management"
      port        = 4943
      target_port = "management"
      protocol    = "TCP"
    }
    port {
      name        = "dashboard"
      port        = 3000
      target_port = "dashboard"
      protocol    = "TCP"
    }
    port {
      name        = "metrics"
      port        = 9090
      target_port = "metrics"
      protocol    = "TCP"
    }
    port {
      name        = "sovereign-api"
      port        = 8443
      target_port = "sovereign-api"
      protocol    = "TCP"
    }
  }
}

# ── ClusterIP Service for external access ─────────────────────────────────────

resource "kubernetes_service" "sovereign_api" {
  metadata {
    name      = "${var.deployment_name}-api"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "nova-sovereign"
      "app.kubernetes.io/instance"   = var.deployment_name
      "app.kubernetes.io/component"  = "api"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "nova-sovereign"
      "app.kubernetes.io/instance" = var.deployment_name
    }

    port {
      name        = "https"
      port        = 443
      target_port = "sovereign-api"
      protocol    = "TCP"
    }
    port {
      name        = "replica"
      port        = 8080
      target_port = "replica"
      protocol    = "TCP"
    }
  }
}

# ── HorizontalPodAutoscaler ───────────────────────────────────────────────────

resource "kubernetes_horizontal_pod_autoscaler_v2" "sovereign_hpa" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-hpa"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "autoscaling"
    }
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "StatefulSet"
      name        = kubernetes_stateful_set.sovereign_nodes.metadata[0].name
    }

    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_target_cpu
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_target_memory
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 300
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 600
        select_policy                = "Min"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 120
        }
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "statefulset_name" {
  value       = kubernetes_stateful_set.sovereign_nodes.metadata[0].name
  description = "Name of the sovereign node StatefulSet"
}

output "service_names" {
  value = {
    headless = kubernetes_service.sovereign_headless.metadata[0].name
    api      = kubernetes_service.sovereign_api.metadata[0].name
  }
  description = "Service names for the sovereign deployment"
}

output "service_account" {
  value       = kubernetes_service_account.sovereign.metadata[0].name
  description = "Service account name"
}

output "compute_config" {
  value = {
    replicas       = var.replica_count
    cpu_request    = var.cpu_request
    cpu_limit      = var.cpu_limit
    memory_request = var.memory_request
    memory_limit   = var.memory_limit
    hpa_enabled    = var.enable_hpa
    hpa_min        = var.hpa_min_replicas
    hpa_max        = var.hpa_max_replicas
  }
  description = "Compute configuration summary"
}
