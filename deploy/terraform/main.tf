# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Cloud Terraform Module
# Cloud-agnostic infrastructure provisioning for governments and enterprises
# ═══════════════════════════════════════════════════════════════════════════════
#
# Supported providers:
#   - AWS GovCloud
#   - Azure Government
#   - GCP Assured Workloads
#   - Oracle Cloud Infrastructure (Government)
#   - Private/On-Premises (via generic provider)
#
# Usage:
#   terraform init
#   terraform plan -var-file="sovereign.tfvars"
#   terraform apply -var-file="sovereign.tfvars"
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "deployment_name" {
  description = "Name of the sovereign NOVA deployment"
  type        = string
  default     = "nova-sovereign"
}

variable "namespace" {
  description = "Kubernetes namespace for sovereign deployment"
  type        = string
  default     = "nova-sovereign"
}

variable "jurisdiction" {
  description = "Data sovereignty jurisdiction (ISO 3166-1 alpha-2)"
  type        = string
  default     = "XX"
}

variable "classification_level" {
  description = "Security classification: unclassified, cui, secret, top-secret"
  type        = string
  default     = "unclassified"
  validation {
    condition     = contains(["unclassified", "cui", "secret", "top-secret"], var.classification_level)
    error_message = "Classification must be: unclassified, cui, secret, or top-secret."
  }
}

variable "cloud_provider" {
  description = "Target cloud: aws-govcloud, azure-gov, gcp-assured, oci-gov, private"
  type        = string
  default     = "private"
}

variable "replica_count" {
  description = "Number of sovereign node replicas"
  type        = number
  default     = 3
}

variable "enable_airgapped" {
  description = "Enable air-gapped deployment mode (no external network access)"
  type        = bool
  default     = false
}

variable "enable_mtls" {
  description = "Enable mutual TLS for zero-trust communication"
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to access the sovereign admin interface"
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "Number of days to retain encrypted backups"
  type        = number
  default     = 90
}

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "sovereign" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "sovereignty/jurisdiction"     = var.jurisdiction
      "sovereignty/classification"   = var.classification_level
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
    annotations = {
      "nova.sovereign/provider"       = var.cloud_provider
      "nova.sovereign/airgapped"      = tostring(var.enable_airgapped)
    }
  }
}

# ── TLS Certificates ─────────────────────────────────────────────────────────

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "NOVA Sovereign CA"
    organization = "NOVA Protocol Sovereign Authority"
    country      = var.jurisdiction
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "nova-sovereign.${var.namespace}.svc.cluster.local"
    organization = "NOVA Sovereign Node"
    country      = var.jurisdiction
  }

  dns_names = [
    "nova-sovereign",
    "nova-sovereign.${var.namespace}",
    "nova-sovereign.${var.namespace}.svc.cluster.local",
    "*.nova-sovereign.${var.namespace}.svc.cluster.local",
  ]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

resource "kubernetes_secret" "tls_certs" {
  metadata {
    name      = "nova-tls-certs"
    namespace = kubernetes_namespace.sovereign.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.server.cert_pem
    "tls.key" = tls_private_key.server.private_key_pem
    "ca.crt"  = tls_self_signed_cert.ca.cert_pem
  }
}

# ── Database Secrets ──────────────────────────────────────────────────────────

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "random_password" "grafana_password" {
  length  = 24
  special = true
}

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name      = "nova-db-credentials"
    namespace = kubernetes_namespace.sovereign.metadata[0].name
  }

  data = {
    password = random_password.db_password.result
  }
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "nova-grafana-admin"
    namespace = kubernetes_namespace.sovereign.metadata[0].name
  }

  data = {
    password = random_password.grafana_password.result
  }
}

# ── Helm Release ──────────────────────────────────────────────────────────────

resource "helm_release" "nova_sovereign" {
  name      = var.deployment_name
  namespace = kubernetes_namespace.sovereign.metadata[0].name
  chart     = "${path.module}/../kubernetes"

  values = [
    yamlencode({
      global = {
        jurisdiction        = var.jurisdiction
        cloudProvider       = var.cloud_provider
        classificationLevel = var.classification_level
      }
      sovereign = {
        replicaCount = var.replica_count
      }
      tls = {
        enabled = true
        mtls = {
          enabled = var.enable_mtls
        }
      }
      monitoring = {
        enabled = true
      }
      backup = {
        enabled       = true
        retentionDays = var.backup_retention_days
      }
      airgapped = {
        enabled = var.enable_airgapped
      }
    })
  ]

  depends_on = [
    kubernetes_secret.tls_certs,
    kubernetes_secret.db_credentials,
  ]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "namespace" {
  value       = kubernetes_namespace.sovereign.metadata[0].name
  description = "Kubernetes namespace for the sovereign deployment"
}

output "ca_certificate" {
  value       = tls_self_signed_cert.ca.cert_pem
  description = "CA certificate for client trust configuration"
  sensitive   = true
}

output "deployment_info" {
  value = {
    name            = var.deployment_name
    jurisdiction    = var.jurisdiction
    classification  = var.classification_level
    cloud_provider  = var.cloud_provider
    replicas        = var.replica_count
    mtls_enabled    = var.enable_mtls
    airgapped       = var.enable_airgapped
  }
  description = "Summary of sovereign deployment configuration"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Module References — Deep Infrastructure Modules
# ═══════════════════════════════════════════════════════════════════════════════

module "networking" {
  source = "./modules/networking"

  deployment_name      = var.deployment_name
  namespace            = kubernetes_namespace.sovereign.metadata[0].name
  jurisdiction         = var.jurisdiction
  enable_airgapped     = var.enable_airgapped
  classification_level = var.classification_level
}

module "security" {
  source = "./modules/security"

  deployment_name      = var.deployment_name
  namespace            = kubernetes_namespace.sovereign.metadata[0].name
  jurisdiction         = var.jurisdiction
  classification_level = var.classification_level
}

module "monitoring" {
  source = "./modules/monitoring"

  deployment_name  = var.deployment_name
  namespace        = kubernetes_namespace.sovereign.metadata[0].name
}

module "compute" {
  source = "./modules/compute"

  deployment_name      = var.deployment_name
  namespace            = kubernetes_namespace.sovereign.metadata[0].name
  replica_count        = var.replica_count
  classification_level = var.classification_level
  jurisdiction         = var.jurisdiction
}

module "storage" {
  source = "./modules/storage"

  deployment_name      = var.deployment_name
  namespace            = kubernetes_namespace.sovereign.metadata[0].name
  jurisdiction         = var.jurisdiction
}

module "governance" {
  source = "./modules/governance"

  deployment_name      = var.deployment_name
  namespace            = kubernetes_namespace.sovereign.metadata[0].name
  jurisdiction         = var.jurisdiction
  classification_level = var.classification_level
}
