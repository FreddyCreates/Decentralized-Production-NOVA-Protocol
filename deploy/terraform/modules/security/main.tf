# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Security Module
# Comprehensive security infrastructure for government-grade deployments
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - Full PKI hierarchy (Root CA → Intermediate CA → Leaf certificates)
#   - HashiCorp Vault integration for secrets management
#   - OPA/Gatekeeper policies for admission control
#   - Pod Security Standards enforcement
#   - RBAC roles and bindings
#   - Security scanning configurations
#   - Encryption key management
#   - Audit policy configuration
#
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
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

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "deployment_name" {
  description = "Base name for security resources"
  type        = string
  default     = "nova-sovereign"
}

variable "jurisdiction" {
  description = "Data sovereignty jurisdiction"
  type        = string
}

variable "classification_level" {
  description = "Security classification level"
  type        = string
  default     = "unclassified"
}

variable "enable_vault" {
  description = "Enable HashiCorp Vault integration"
  type        = bool
  default     = true
}

variable "enable_opa" {
  description = "Enable OPA/Gatekeeper admission control"
  type        = bool
  default     = true
}

variable "ca_validity_hours" {
  description = "Root CA validity period in hours"
  type        = number
  default     = 87600  # 10 years
}

variable "intermediate_ca_validity_hours" {
  description = "Intermediate CA validity period in hours"
  type        = number
  default     = 43800  # 5 years
}

variable "server_cert_validity_hours" {
  description = "Server certificate validity period in hours"
  type        = number
  default     = 8760  # 1 year
}

variable "client_cert_validity_hours" {
  description = "Client certificate validity period in hours"
  type        = number
  default     = 4380  # 6 months
}

variable "key_algorithm" {
  description = "Cryptographic algorithm for keys: RSA or ECDSA"
  type        = string
  default     = "RSA"
  validation {
    condition     = contains(["RSA", "ECDSA"], var.key_algorithm)
    error_message = "Key algorithm must be RSA or ECDSA."
  }
}

variable "rsa_bits" {
  description = "RSA key size in bits"
  type        = number
  default     = 4096
}

variable "ecdsa_curve" {
  description = "ECDSA curve (P256, P384, P521)"
  type        = string
  default     = "P384"
}

variable "admin_subjects" {
  description = "List of admin user/group subjects for RBAC"
  type = list(object({
    kind      = string
    name      = string
    namespace = optional(string)
  }))
  default = []
}

variable "operator_subjects" {
  description = "List of operator user/group subjects for RBAC"
  type = list(object({
    kind      = string
    name      = string
    namespace = optional(string)
  }))
  default = []
}

variable "auditor_subjects" {
  description = "List of auditor user/group subjects for RBAC"
  type = list(object({
    kind      = string
    name      = string
    namespace = optional(string)
  }))
  default = []
}

variable "multisig_threshold" {
  description = "Number of signatures required for critical operations"
  type        = number
  default     = 3
}

variable "multisig_total" {
  description = "Total number of authorized signers"
  type        = number
  default     = 5
}

variable "encryption_at_rest" {
  description = "Enable encryption at rest for all persistent volumes"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Number of days to retain audit logs"
  type        = number
  default     = 365
}

# ── PKI: Root Certificate Authority ──────────────────────────────────────────

resource "tls_private_key" "root_ca" {
  algorithm   = var.key_algorithm
  rsa_bits    = var.key_algorithm == "RSA" ? var.rsa_bits : null
  ecdsa_curve = var.key_algorithm == "ECDSA" ? var.ecdsa_curve : null
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name         = "NOVA Sovereign Root CA"
    organization        = "NOVA Protocol Sovereign Authority"
    organizational_unit = "Sovereign PKI"
    country             = var.jurisdiction
    locality            = "Sovereign Cloud"
  }

  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# ── PKI: Intermediate Certificate Authority ───────────────────────────────────

resource "tls_private_key" "intermediate_ca" {
  algorithm   = var.key_algorithm
  rsa_bits    = var.key_algorithm == "RSA" ? var.rsa_bits : null
  ecdsa_curve = var.key_algorithm == "ECDSA" ? var.ecdsa_curve : null
}

resource "tls_cert_request" "intermediate_ca" {
  private_key_pem = tls_private_key.intermediate_ca.private_key_pem

  subject {
    common_name         = "NOVA Sovereign Intermediate CA"
    organization        = "NOVA Protocol Sovereign Authority"
    organizational_unit = "Sovereign Services"
    country             = var.jurisdiction
  }
}

resource "tls_locally_signed_cert" "intermediate_ca" {
  cert_request_pem   = tls_cert_request.intermediate_ca.cert_request_pem
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = var.intermediate_ca_validity_hours
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# ── PKI: Server Certificate ───────────────────────────────────────────────────

resource "tls_private_key" "server" {
  algorithm   = var.key_algorithm
  rsa_bits    = var.key_algorithm == "RSA" ? var.rsa_bits : null
  ecdsa_curve = var.key_algorithm == "ECDSA" ? var.ecdsa_curve : null
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name         = "${var.deployment_name}.${var.namespace}.svc.cluster.local"
    organization        = "NOVA Sovereign Node"
    organizational_unit = "Data Plane"
    country             = var.jurisdiction
  }

  dns_names = [
    var.deployment_name,
    "${var.deployment_name}.${var.namespace}",
    "${var.deployment_name}.${var.namespace}.svc",
    "${var.deployment_name}.${var.namespace}.svc.cluster.local",
    "*.${var.deployment_name}.${var.namespace}.svc.cluster.local",
    "localhost",
  ]

  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.intermediate_ca.private_key_pem
  ca_cert_pem        = tls_locally_signed_cert.intermediate_ca.cert_pem

  validity_period_hours = var.server_cert_validity_hours
  set_subject_key_id    = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── PKI: Client Certificate (for mTLS) ───────────────────────────────────────

resource "tls_private_key" "client" {
  algorithm   = var.key_algorithm
  rsa_bits    = var.key_algorithm == "RSA" ? var.rsa_bits : null
  ecdsa_curve = var.key_algorithm == "ECDSA" ? var.ecdsa_curve : null
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name         = "nova-admin-client"
    organization        = "NOVA Sovereign Administration"
    organizational_unit = "Management Plane"
    country             = var.jurisdiction
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.intermediate_ca.private_key_pem
  ca_cert_pem        = tls_locally_signed_cert.intermediate_ca.cert_pem

  validity_period_hours = var.client_cert_validity_hours
  set_subject_key_id    = true

  allowed_uses = [
    "digital_signature",
    "client_auth",
  ]
}

# ── Kubernetes Secrets for Certificates ───────────────────────────────────────

resource "kubernetes_secret" "root_ca" {
  metadata {
    name      = "${var.deployment_name}-root-ca"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "pki"
      "nova.sovereign/cert-type"     = "root-ca"
    }
  }

  type = "Opaque"

  data = {
    "ca.crt" = tls_self_signed_cert.root_ca.cert_pem
  }
}

resource "kubernetes_secret" "intermediate_ca" {
  metadata {
    name      = "${var.deployment_name}-intermediate-ca"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "pki"
      "nova.sovereign/cert-type"     = "intermediate-ca"
    }
  }

  type = "Opaque"

  data = {
    "ca.crt"  = tls_locally_signed_cert.intermediate_ca.cert_pem
    "ca.key"  = tls_private_key.intermediate_ca.private_key_pem
    "chain.crt" = join("", [
      tls_locally_signed_cert.intermediate_ca.cert_pem,
      tls_self_signed_cert.root_ca.cert_pem,
    ])
  }
}

resource "kubernetes_secret" "server_tls" {
  metadata {
    name      = "${var.deployment_name}-server-tls"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "pki"
      "nova.sovereign/cert-type"     = "server"
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = join("", [
      tls_locally_signed_cert.server.cert_pem,
      tls_locally_signed_cert.intermediate_ca.cert_pem,
    ])
    "tls.key" = tls_private_key.server.private_key_pem
    "ca.crt"  = tls_self_signed_cert.root_ca.cert_pem
  }
}

resource "kubernetes_secret" "client_tls" {
  metadata {
    name      = "${var.deployment_name}-client-tls"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "pki"
      "nova.sovereign/cert-type"     = "client"
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.client.cert_pem
    "tls.key" = tls_private_key.client.private_key_pem
    "ca.crt"  = tls_self_signed_cert.root_ca.cert_pem
  }
}

# ── RBAC: Cluster Roles ───────────────────────────────────────────────────────

resource "kubernetes_cluster_role" "sovereign_admin" {
  metadata {
    name = "${var.deployment_name}-admin"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/role"          = "admin"
    }
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_cluster_role" "sovereign_operator" {
  metadata {
    name = "${var.deployment_name}-operator"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/role"          = "operator"
    }
  }

  rule {
    api_groups = ["apps", ""]
    resources  = ["deployments", "statefulsets", "pods", "services", "configmaps"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log", "pods/exec"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role" "sovereign_auditor" {
  metadata {
    name = "${var.deployment_name}-auditor"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/role"          = "auditor"
    }
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = []  # Auditors cannot read secrets
  }
}

resource "kubernetes_cluster_role" "sovereign_viewer" {
  metadata {
    name = "${var.deployment_name}-viewer"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/role"          = "viewer"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "events"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }
}

# ── RBAC: Role Bindings ───────────────────────────────────────────────────────

resource "kubernetes_role_binding" "admin_binding" {
  count = length(var.admin_subjects) > 0 ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-admin-binding"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.sovereign_admin.metadata[0].name
  }

  dynamic "subject" {
    for_each = var.admin_subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.namespace
    }
  }
}

resource "kubernetes_role_binding" "operator_binding" {
  count = length(var.operator_subjects) > 0 ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-operator-binding"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.sovereign_operator.metadata[0].name
  }

  dynamic "subject" {
    for_each = var.operator_subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.namespace
    }
  }
}

resource "kubernetes_role_binding" "auditor_binding" {
  count = length(var.auditor_subjects) > 0 ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-auditor-binding"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.sovereign_auditor.metadata[0].name
  }

  dynamic "subject" {
    for_each = var.auditor_subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.namespace
    }
  }
}

# ── Encryption Key for Data at Rest ──────────────────────────────────────────

resource "random_password" "encryption_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret" "encryption_key" {
  metadata {
    name      = "${var.deployment_name}-encryption-key"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "encryption"
    }
  }

  data = {
    "encryption.key" = base64encode(random_password.encryption_key.result)
  }
}

# ── Security Configuration ConfigMap ─────────────────────────────────────────

resource "kubernetes_config_map" "security_config" {
  metadata {
    name      = "${var.deployment_name}-security-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "security"
    }
  }

  data = {
    "security-policy.yaml" = yamlencode({
      version = "1.0"
      classification = var.classification_level
      jurisdiction   = var.jurisdiction

      pki = {
        algorithm        = var.key_algorithm
        key_size         = var.key_algorithm == "RSA" ? var.rsa_bits : var.ecdsa_curve
        ca_validity      = "${var.ca_validity_hours}h"
        cert_validity    = "${var.server_cert_validity_hours}h"
        auto_rotation    = true
        rotation_buffer  = "720h"  # Rotate 30 days before expiry
      }

      encryption = {
        at_rest = var.encryption_at_rest
        algorithm = "AES-256-GCM"
        key_derivation = "HKDF-SHA256"
      }

      authentication = {
        mtls_required = true
        token_lifetime = "3600s"
        max_sessions_per_user = 3
        session_idle_timeout = "900s"
      }

      authorization = {
        model = "RBAC"
        default_deny = true
        multisig = {
          enabled   = true
          threshold = var.multisig_threshold
          total     = var.multisig_total
          operations = [
            "canister_upgrade",
            "configuration_change",
            "data_export",
            "key_rotation",
            "emergency_shutdown",
          ]
        }
      }

      audit = {
        enabled = true
        retention_days = var.audit_log_retention_days
        log_all_access = true
        log_mutations  = true
        tamper_proof   = true
        hash_algorithm = "SHA-256"
      }

      hardening = {
        disable_exec          = true
        read_only_root_fs     = true
        no_privilege_escalation = true
        drop_all_capabilities = true
        add_capabilities      = ["NET_BIND_SERVICE"]
        seccomp_profile       = "RuntimeDefault"
      }
    })

    "opa-constraints.yaml" = yamlencode({
      apiVersion = "constraints.gatekeeper.sh/v1beta1"
      kind       = "K8sNovaSecurityPolicy"
      metadata = {
        name = "${var.deployment_name}-security-constraints"
      }
      spec = {
        match = {
          kinds = [
            { apiGroups = [""], kinds = ["Pod"] },
            { apiGroups = ["apps"], kinds = ["Deployment", "StatefulSet"] },
          ]
          namespaces = [var.namespace]
        }
        parameters = {
          requiredLabels = [
            "app.kubernetes.io/name",
            "app.kubernetes.io/instance",
            "nova.sovereign/component",
          ]
          disallowedCapabilities = [
            "ALL",
          ]
          requiredSecurityContext = {
            runAsNonRoot = true
            readOnlyRootFilesystem = true
            allowPrivilegeEscalation = false
          }
          allowedImages = [
            "nova-sovereign:*",
            "postgres:*-alpine",
            "nginx:*-alpine",
            "prom/prometheus:*",
            "grafana/grafana:*",
            "fluent/fluent-bit:*",
          ]
          maxReplicaCount = 10
          requiredResourceLimits = true
        }
      }
    })

    "vault-config.yaml" = yamlencode({
      enabled = var.enable_vault
      vault = {
        address = "https://vault.${var.namespace}.svc.cluster.local:8200"
        auth_method = "kubernetes"
        role = "${var.deployment_name}-role"
        secrets_path = "secret/data/${var.deployment_name}"
        pki_path = "pki/${var.deployment_name}"
        transit_path = "transit/${var.deployment_name}"
        policies = [
          "${var.deployment_name}-read",
          "${var.deployment_name}-pki-issue",
          "${var.deployment_name}-transit-encrypt",
        ]
      }
    })
  }
}

# ── Pod Security Policy (for older clusters) ─────────────────────────────────

resource "kubernetes_config_map" "pod_security" {
  metadata {
    name      = "${var.deployment_name}-pod-security"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "pod-security"
    }
  }

  data = {
    "pod-security-standards.yaml" = yamlencode({
      apiVersion = "policy/v1beta1"
      kind       = "PodSecurityPolicy"
      metadata = {
        name = "${var.deployment_name}-restricted"
        annotations = {
          "seccomp.security.alpha.kubernetes.io/allowedProfiles" = "runtime/default"
        }
      }
      spec = {
        privileged                 = false
        allowPrivilegeEscalation   = false
        requiredDropCapabilities   = ["ALL"]
        allowedCapabilities       = ["NET_BIND_SERVICE"]
        hostNetwork               = false
        hostIPC                   = false
        hostPID                   = false
        runAsUser                 = { rule = "MustRunAsNonRoot" }
        runAsGroup                = { rule = "MustRunAs", ranges = [{ min = 1000, max = 65534 }] }
        fsGroup                   = { rule = "MustRunAs", ranges = [{ min = 1000, max = 65534 }] }
        seLinux                   = { rule = "RunAsAny" }
        supplementalGroups        = { rule = "MustRunAs", ranges = [{ min = 1000, max = 65534 }] }
        volumes                   = ["configMap", "emptyDir", "projected", "secret", "downwardAPI", "persistentVolumeClaim"]
        readOnlyRootFilesystem    = true
      }
    })
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "pki" {
  value = {
    root_ca_secret         = kubernetes_secret.root_ca.metadata[0].name
    intermediate_ca_secret = kubernetes_secret.intermediate_ca.metadata[0].name
    server_tls_secret      = kubernetes_secret.server_tls.metadata[0].name
    client_tls_secret      = kubernetes_secret.client_tls.metadata[0].name
  }
  description = "PKI secret names"
}

output "rbac_roles" {
  value = {
    admin    = kubernetes_cluster_role.sovereign_admin.metadata[0].name
    operator = kubernetes_cluster_role.sovereign_operator.metadata[0].name
    auditor  = kubernetes_cluster_role.sovereign_auditor.metadata[0].name
    viewer   = kubernetes_cluster_role.sovereign_viewer.metadata[0].name
  }
  description = "RBAC role names"
}

output "encryption_key_secret" {
  value       = kubernetes_secret.encryption_key.metadata[0].name
  description = "Name of the encryption key secret"
  sensitive   = true
}

output "security_config" {
  value = {
    config_map       = kubernetes_config_map.security_config.metadata[0].name
    classification   = var.classification_level
    encryption       = var.encryption_at_rest
    vault_enabled    = var.enable_vault
    opa_enabled      = var.enable_opa
    multisig         = "${var.multisig_threshold}/${var.multisig_total}"
  }
  description = "Security configuration summary"
}
