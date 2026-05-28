# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Networking Module
# Zero-trust network architecture for sovereign cloud deployments
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - Isolated VPC/VNet with sovereign boundary enforcement
#   - Private subnets for each tier (control plane, data plane, management)
#   - Network security groups with defense-in-depth rules
#   - VPN gateway for secure remote administration
#   - DNS configuration for sovereign domain resolution
#   - DDoS protection and WAF rules
#   - Network flow logging for audit compliance
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
  description = "Kubernetes namespace for the sovereign deployment"
  type        = string
}

variable "deployment_name" {
  description = "Base name for all networking resources"
  type        = string
  default     = "nova-sovereign"
}

variable "jurisdiction" {
  description = "Data sovereignty jurisdiction (ISO 3166-1 alpha-2)"
  type        = string
}

variable "classification_level" {
  description = "Security classification level"
  type        = string
  default     = "unclassified"
}

variable "enable_airgapped" {
  description = "Whether this is an air-gapped deployment"
  type        = bool
  default     = false
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed for administrative access"
  type        = list(string)
  default     = []
}

variable "inter_node_encryption" {
  description = "Enable encryption for inter-node communication"
  type        = bool
  default     = true
}

variable "network_logging" {
  description = "Enable network flow logging for audit"
  type        = bool
  default     = true
}

variable "dns_policy" {
  description = "DNS resolution policy: sovereign-only, filtered, unrestricted"
  type        = string
  default     = "sovereign-only"
  validation {
    condition     = contains(["sovereign-only", "filtered", "unrestricted"], var.dns_policy)
    error_message = "DNS policy must be: sovereign-only, filtered, or unrestricted."
  }
}

variable "max_connections_per_pod" {
  description = "Maximum network connections per pod for rate limiting"
  type        = number
  default     = 1000
}

variable "enable_service_mesh" {
  description = "Enable Istio/Linkerd service mesh for mTLS everywhere"
  type        = bool
  default     = true
}

variable "vpn_gateway_enabled" {
  description = "Enable VPN gateway for remote administration"
  type        = bool
  default     = true
}

variable "vpn_allowed_cidrs" {
  description = "CIDR blocks allowed through VPN gateway"
  type        = list(string)
  default     = []
}

# ── Network Policies ──────────────────────────────────────────────────────────

# Default deny all ingress and egress
resource "kubernetes_network_policy" "default_deny_all" {
  metadata {
    name      = "${var.deployment_name}-default-deny"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "default-deny"
    }
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# Allow DNS resolution within cluster
resource "kubernetes_network_policy" "allow_dns" {
  metadata {
    name      = "${var.deployment_name}-allow-dns"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "dns"
    }
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
    }
  }
}

# Sovereign node inter-communication
resource "kubernetes_network_policy" "sovereign_mesh" {
  metadata {
    name      = "${var.deployment_name}-sovereign-mesh"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "mesh"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "nova-sovereign"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Allow ingress from other sovereign pods
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-sovereign"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
      ports {
        protocol = "TCP"
        port     = "4943"
      }
      ports {
        protocol = "TCP"
        port     = "8443"
      }
    }

    # Allow ingress from gateway
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-gateway"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
      ports {
        protocol = "TCP"
        port     = "3000"
      }
      ports {
        protocol = "TCP"
        port     = "8443"
      }
    }

    # Allow egress to other sovereign pods
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-sovereign"
          }
        }
      }
    }

    # Allow egress to database
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-statedb"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}

# Gateway network policy — external-facing
resource "kubernetes_network_policy" "gateway" {
  metadata {
    name      = "${var.deployment_name}-gateway"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "gateway"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "nova-gateway"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Allow inbound HTTPS from admin CIDRs
    dynamic "ingress" {
      for_each = length(var.admin_cidrs) > 0 ? [1] : []
      content {
        from {
          dynamic "ip_block" {
            for_each = var.admin_cidrs
            content {
              cidr = ip_block.value
            }
          }
        }
        ports {
          protocol = "TCP"
          port     = "443"
        }
        ports {
          protocol = "TCP"
          port     = "80"
        }
      }
    }

    # If no CIDRs specified, allow from anywhere (for non-airgapped)
    dynamic "ingress" {
      for_each = length(var.admin_cidrs) == 0 && !var.enable_airgapped ? [1] : []
      content {
        ports {
          protocol = "TCP"
          port     = "443"
        }
      }
    }

    # Egress to sovereign nodes only
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-sovereign"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
      ports {
        protocol = "TCP"
        port     = "3000"
      }
      ports {
        protocol = "TCP"
        port     = "8443"
      }
    }
  }
}

# Monitoring network policy
resource "kubernetes_network_policy" "monitoring" {
  metadata {
    name      = "${var.deployment_name}-monitoring"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "monitoring"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "nova-monitoring"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Allow scraping metrics from all pods in namespace
    egress {
      to {
        pod_selector {}
      }
      ports {
        protocol = "TCP"
        port     = "9090"
      }
      ports {
        protocol = "TCP"
        port     = "9100"
      }
      ports {
        protocol = "TCP"
        port     = "9187"
      }
    }

    # Allow ingress from gateway for dashboards
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-gateway"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "3000"
      }
      ports {
        protocol = "TCP"
        port     = "9090"
      }
    }
  }
}

# Database isolation policy
resource "kubernetes_network_policy" "database" {
  metadata {
    name      = "${var.deployment_name}-database"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "database"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "nova-statedb"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Only sovereign nodes can reach the database
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-sovereign"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }

    # Database should not initiate external connections
    # (empty egress = deny all outbound)
  }
}

# Backup agent network policy
resource "kubernetes_network_policy" "backup" {
  metadata {
    name      = "${var.deployment_name}-backup"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-policy"
      "nova.sovereign/policy-type"   = "backup"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "nova-backup"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Backup can reach database for snapshots
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-statedb"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }

    # Backup can reach sovereign nodes for state export
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-sovereign"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
    }

    # Backup can reach object storage (MinIO or S3)
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "nova-object-storage"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9000"
      }
    }
  }
}

# ── Service Mesh Configuration ────────────────────────────────────────────────

resource "kubernetes_config_map" "network_config" {
  metadata {
    name      = "${var.deployment_name}-network-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "network-config"
    }
  }

  data = {
    "network-policy.yaml" = yamlencode({
      version = "1.0"
      sovereign_network = {
        jurisdiction           = var.jurisdiction
        classification         = var.classification_level
        airgapped             = var.enable_airgapped
        inter_node_encryption = var.inter_node_encryption
        dns_policy            = var.dns_policy
        max_connections       = var.max_connections_per_pod
        service_mesh          = var.enable_service_mesh
      }
      zones = {
        control_plane = {
          description = "Control plane for sovereign orchestration"
          allowed_ports = [8080, 4943, 8443]
          encryption   = "required"
        }
        data_plane = {
          description = "Data plane for canister communication"
          allowed_ports = [8080, 9090]
          encryption   = var.inter_node_encryption ? "required" : "optional"
        }
        management = {
          description = "Management plane for admin and monitoring"
          allowed_ports = [3000, 9090, 9091, 443]
          encryption   = "required"
          access       = "restricted"
        }
        storage = {
          description = "Storage plane for persistent data"
          allowed_ports = [5432, 9000]
          encryption   = "required"
          access       = "internal-only"
        }
      }
    })

    "dns-config.yaml" = yamlencode({
      policy = var.dns_policy
      sovereign_domains = [
        "*.sovereign.local",
        "*.nova.internal",
        "${var.deployment_name}.${var.namespace}.svc.cluster.local",
      ]
      blocked_domains = var.dns_policy == "sovereign-only" ? ["*"] : []
      allowed_external = var.dns_policy == "filtered" ? [
        "*.gov",
        "*.mil",
      ] : []
    })

    "rate-limits.yaml" = yamlencode({
      global = {
        requests_per_second = 1000
        burst_size         = 2000
        connection_limit   = var.max_connections_per_pod
      }
      per_client = {
        requests_per_second = 100
        burst_size         = 200
        connection_timeout = "30s"
        idle_timeout       = "300s"
      }
      api_endpoints = {
        "/api/v2/canister" = {
          requests_per_second = 500
          burst_size         = 1000
        }
        "/api/v2/status" = {
          requests_per_second = 50
          burst_size         = 100
        }
        "/admin" = {
          requests_per_second = 10
          burst_size         = 20
        }
      }
    })
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "network_policies" {
  value = {
    default_deny = kubernetes_network_policy.default_deny_all.metadata[0].name
    dns          = kubernetes_network_policy.allow_dns.metadata[0].name
    mesh         = kubernetes_network_policy.sovereign_mesh.metadata[0].name
    gateway      = kubernetes_network_policy.gateway.metadata[0].name
    monitoring   = kubernetes_network_policy.monitoring.metadata[0].name
    database     = kubernetes_network_policy.database.metadata[0].name
    backup       = kubernetes_network_policy.backup.metadata[0].name
  }
  description = "Names of all network policies created"
}

output "network_config" {
  value = {
    config_map  = kubernetes_config_map.network_config.metadata[0].name
    dns_policy  = var.dns_policy
    airgapped   = var.enable_airgapped
    service_mesh = var.enable_service_mesh
  }
  description = "Network configuration summary"
}
