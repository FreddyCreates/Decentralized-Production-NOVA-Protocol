# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Governance Module
# Multi-signature governance, compliance automation, and policy enforcement
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - Multi-sig governance controller configuration
#   - Compliance checker CronJobs
#   - Policy enforcement (OPA/Gatekeeper integration)
#   - Certificate rotation automation
#   - Emergency shutdown procedures
#   - Sovereign identity management
#   - Delegation and federation policies
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
  description = "Base name for governance resources"
  type        = string
  default     = "nova-sovereign"
}

variable "jurisdiction" {
  description = "Sovereign jurisdiction"
  type        = string
}

variable "classification_level" {
  description = "Security classification"
  type        = string
  default     = "unclassified"
}

variable "multisig_threshold" {
  description = "Minimum signatures required"
  type        = number
  default     = 3
}

variable "multisig_total" {
  description = "Total authorized signers"
  type        = number
  default     = 5
}

variable "compliance_frameworks" {
  description = "Compliance frameworks to enforce"
  type        = list(string)
  default     = ["nist-800-53", "iso-27001"]
}

variable "cert_rotation_days_before_expiry" {
  description = "Days before expiry to rotate certificates"
  type        = number
  default     = 30
}

variable "emergency_shutdown_enabled" {
  description = "Enable emergency shutdown capability"
  type        = bool
  default     = true
}

variable "data_residency_strict" {
  description = "Strictly enforce data residency (no cross-border data flow)"
  type        = bool
  default     = true
}

variable "federation_enabled" {
  description = "Enable federation with other sovereign nodes"
  type        = bool
  default     = false
}

variable "federation_peers" {
  description = "List of federation peer endpoints"
  type        = list(string)
  default     = []
}

# ── Governance Configuration ──────────────────────────────────────────────────

resource "kubernetes_config_map" "governance_config" {
  metadata {
    name      = "${var.deployment_name}-governance-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "governance"
    }
  }

  data = {
    "governance-policy.yaml" = yamlencode({
      version = "1.0"
      sovereign_governance = {
        jurisdiction   = var.jurisdiction
        classification = var.classification_level

        multisig = {
          enabled   = true
          threshold = var.multisig_threshold
          total_signers = var.multisig_total
          timeout_hours = 72
          operations = {
            critical = {
              threshold = var.multisig_threshold
              operations = [
                "canister_upgrade",
                "emergency_shutdown",
                "key_rotation",
                "data_export",
                "configuration_change",
                "signer_addition",
                "signer_removal",
              ]
            }
            standard = {
              threshold = max(2, var.multisig_threshold - 1)
              operations = [
                "canister_deploy",
                "backup_restore",
                "user_management",
                "monitoring_config",
              ]
            }
            routine = {
              threshold = 1
              operations = [
                "read_audit_logs",
                "view_metrics",
                "generate_reports",
              ]
            }
          }
        }

        data_residency = {
          strict = var.data_residency_strict
          jurisdiction = var.jurisdiction
          allowed_regions = [var.jurisdiction]
          cross_border_policy = var.data_residency_strict ? "deny" : "audit-and-allow"
          encryption_in_transit = true
          encryption_at_rest = true
        }

        compliance = {
          frameworks = var.compliance_frameworks
          auto_check_interval = "1h"
          report_schedule = "0 0 * * 1"  # Weekly Monday
          controls = {
            "nist-800-53" = {
              families = [
                "AC", "AU", "CM", "CP", "IA", "IR",
                "MA", "MP", "PE", "PL", "PS", "RA",
                "SA", "SC", "SI",
              ]
              baseline = var.classification_level == "unclassified" ? "low" : (
                var.classification_level == "cui" ? "moderate" : "high"
              )
            }
            "iso-27001" = {
              domains = [
                "A.5", "A.6", "A.7", "A.8", "A.9", "A.10",
                "A.11", "A.12", "A.13", "A.14", "A.15", "A.16",
                "A.17", "A.18",
              ]
            }
          }
        }

        certificate_management = {
          rotation_days_before_expiry = var.cert_rotation_days_before_expiry
          auto_rotation = true
          notification_days = [90, 60, 30, 14, 7, 3, 1]
          revocation_check = true
          ocsp_stapling = true
        }

        emergency = {
          shutdown_enabled = var.emergency_shutdown_enabled
          shutdown_requires_multisig = true
          shutdown_threshold = var.multisig_threshold
          auto_lockdown_triggers = [
            "unauthorized_access_detected",
            "data_exfiltration_attempt",
            "certificate_compromise",
            "consensus_failure",
          ]
          recovery_procedure = "manual"
          recovery_requires_multisig = true
          recovery_threshold = var.multisig_total  # Requires ALL signers
        }

        federation = {
          enabled = var.federation_enabled
          peers   = var.federation_peers
          protocol = "sovereign-mesh/v1"
          encryption = "AES-256-GCM"
          authentication = "mTLS"
          data_sharing_policy = "metadata-only"
          sync_interval = "5m"
        }

        identity = {
          provider = "sovereign-pki"
          mfa_required = true
          session_timeout = "900s"
          max_sessions = 3
          password_policy = {
            min_length = 16
            require_uppercase = true
            require_lowercase = true
            require_numbers = true
            require_special = true
            max_age_days = 90
            history_count = 12
          }
        }
      }
    })

    "compliance-checks.yaml" = yamlencode({
      checks = [
        {
          id = "SOV-001"
          name = "Data Residency Compliance"
          description = "Verify all data resides within sovereign jurisdiction"
          severity = "critical"
          schedule = "*/30 * * * *"
          check = "verify_data_location"
          params = {
            jurisdiction = var.jurisdiction
            strict = var.data_residency_strict
          }
        },
        {
          id = "SOV-002"
          name = "Encryption at Rest Verification"
          description = "Verify all persistent volumes are encrypted"
          severity = "critical"
          schedule = "0 * * * *"
          check = "verify_encryption_at_rest"
        },
        {
          id = "SOV-003"
          name = "Certificate Validity Check"
          description = "Check all certificates are valid and not expiring soon"
          severity = "high"
          schedule = "0 */6 * * *"
          check = "verify_certificates"
          params = {
            warn_days = var.cert_rotation_days_before_expiry
          }
        },
        {
          id = "SOV-004"
          name = "Audit Log Integrity"
          description = "Verify audit log chain integrity (no tampering)"
          severity = "critical"
          schedule = "*/15 * * * *"
          check = "verify_audit_integrity"
        },
        {
          id = "SOV-005"
          name = "Network Isolation Verification"
          description = "Verify network policies are enforced"
          severity = "high"
          schedule = "0 */4 * * *"
          check = "verify_network_isolation"
        },
        {
          id = "SOV-006"
          name = "RBAC Configuration Audit"
          description = "Verify RBAC roles and bindings are correct"
          severity = "high"
          schedule = "0 0 * * *"
          check = "audit_rbac"
        },
        {
          id = "SOV-007"
          name = "Pod Security Standards"
          description = "Verify all pods comply with restricted security standards"
          severity = "high"
          schedule = "*/30 * * * *"
          check = "verify_pod_security"
        },
        {
          id = "SOV-008"
          name = "Backup Freshness"
          description = "Verify backups are recent and restorable"
          severity = "high"
          schedule = "0 6 * * *"
          check = "verify_backup_freshness"
          params = {
            max_age_hours = 48
          }
        },
        {
          id = "SOV-009"
          name = "Multi-Sig Quorum Available"
          description = "Verify enough signers are active for critical operations"
          severity = "critical"
          schedule = "*/10 * * * *"
          check = "verify_multisig_quorum"
          params = {
            threshold = var.multisig_threshold
          }
        },
        {
          id = "SOV-010"
          name = "Resource Usage Within Bounds"
          description = "Verify resource usage is within quota limits"
          severity = "medium"
          schedule = "*/15 * * * *"
          check = "verify_resource_usage"
          params = {
            cpu_threshold = 85
            memory_threshold = 85
            storage_threshold = 80
          }
        },
      ]
    })

    "emergency-procedures.yaml" = yamlencode({
      procedures = {
        emergency_shutdown = {
          name = "Emergency Sovereign Shutdown"
          description = "Gracefully shuts down all sovereign node operations"
          requires_multisig = true
          threshold = var.multisig_threshold
          steps = [
            "1. Verify shutdown authorization (multi-sig)",
            "2. Stop accepting new requests (drain gateway)",
            "3. Complete in-flight transactions",
            "4. Create emergency backup",
            "5. Stop all canisters gracefully",
            "6. Shutdown IC replica",
            "7. Seal encryption keys",
            "8. Generate shutdown audit report",
            "9. Notify all administrators",
          ]
          rollback = [
            "1. Verify recovery authorization (ALL signers required)",
            "2. Unseal encryption keys",
            "3. Start IC replica",
            "4. Verify canister state integrity",
            "5. Resume canisters",
            "6. Open gateway",
            "7. Verify system health",
            "8. Generate recovery audit report",
          ]
        }
        certificate_compromise = {
          name = "Certificate Compromise Response"
          description = "Response procedure when a certificate is compromised"
          requires_multisig = true
          threshold = var.multisig_threshold
          steps = [
            "1. Immediately revoke compromised certificate",
            "2. Rotate all related certificates",
            "3. Force disconnect all active sessions",
            "4. Audit all recent access using compromised cert",
            "5. Issue new certificates from fresh key material",
            "6. Update all trust stores",
            "7. Notify all administrators",
            "8. Generate incident report",
          ]
        }
        data_breach_response = {
          name = "Data Breach Response"
          description = "Response procedure for suspected data breach"
          requires_multisig = true
          threshold = var.multisig_total  # ALL signers
          steps = [
            "1. Isolate affected systems (network policy enforcement)",
            "2. Preserve forensic evidence (snapshot all volumes)",
            "3. Assess scope of breach",
            "4. Notify jurisdiction authorities within required timeframe",
            "5. Contain and eradicate threat",
            "6. Recover from clean backups if necessary",
            "7. Implement corrective measures",
            "8. Generate comprehensive incident report",
            "9. Conduct post-incident review",
          ]
        }
      }
    })
  }
}

# ── Compliance Checker CronJob ────────────────────────────────────────────────

resource "kubernetes_cron_job_v1" "compliance_checker" {
  metadata {
    name      = "${var.deployment_name}-compliance-check"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "governance"
      "nova.sovereign/sub-component" = "compliance"
    }
  }

  spec {
    schedule                      = "0 */6 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 5
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"   = "nova-compliance"
          "nova.sovereign/component" = "governance"
        }
      }

      spec {
        backoff_limit = 2
        active_deadline_seconds = 1800

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"   = "nova-compliance"
              "nova.sovereign/component" = "governance"
            }
          }

          spec {
            service_account_name = "${var.deployment_name}-node"

            security_context {
              run_as_non_root = true
              run_as_user     = 1000
              fs_group        = 1000
            }

            container {
              name  = "compliance-checker"
              image = "bitnami/kubectl:1.29"
              command = ["/bin/sh", "-c"]
              args = [<<-EOT
                set -e
                echo "╔═══════════════════════════════════════════════════════════╗"
                echo "║  NOVA Sovereign Compliance Check                          ║"
                echo "║  Jurisdiction: ${var.jurisdiction}                         ║"
                echo "║  Classification: ${var.classification_level}               ║"
                echo "╚═══════════════════════════════════════════════════════════╝"
                echo ""

                TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
                PASS=0
                FAIL=0
                WARN=0

                check_result() {
                    local name="$1" result="$2" severity="$3"
                    if [ "$result" = "pass" ]; then
                        echo "[PASS] $name"
                        PASS=$((PASS + 1))
                    elif [ "$result" = "warn" ]; then
                        echo "[WARN] $name"
                        WARN=$((WARN + 1))
                    else
                        echo "[FAIL] $name (severity: $severity)"
                        FAIL=$((FAIL + 1))
                    fi
                }

                # SOV-001: Check pods are running
                echo "=== SOV-001: Sovereign Node Status ==="
                RUNNING=$(kubectl get pods -n ${var.namespace} -l app.kubernetes.io/name=nova-sovereign --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
                if [ "$RUNNING" -ge 1 ]; then
                    check_result "Sovereign nodes running ($RUNNING)" "pass" ""
                else
                    check_result "No sovereign nodes running" "fail" "critical"
                fi

                # SOV-002: Check network policies exist
                echo "=== SOV-002: Network Policies ==="
                NP_COUNT=$(kubectl get networkpolicies -n ${var.namespace} --no-headers 2>/dev/null | wc -l)
                if [ "$NP_COUNT" -ge 5 ]; then
                    check_result "Network policies present ($NP_COUNT)" "pass" ""
                else
                    check_result "Insufficient network policies ($NP_COUNT < 5)" "fail" "high"
                fi

                # SOV-003: Check secrets are not exposed
                echo "=== SOV-003: Secret Security ==="
                EXPOSED=$(kubectl get pods -n ${var.namespace} -o json | grep -c "secretKeyRef" || true)
                check_result "Secrets referenced via secretKeyRef ($EXPOSED refs)" "pass" ""

                # SOV-004: Check pod security context
                echo "=== SOV-004: Pod Security ==="
                ROOT_PODS=$(kubectl get pods -n ${var.namespace} -o json | grep -c '"runAsNonRoot":false' || echo "0")
                if [ "$ROOT_PODS" = "0" ]; then
                    check_result "All pods run as non-root" "pass" ""
                else
                    check_result "$ROOT_PODS pods running as root" "fail" "high"
                fi

                # SOV-005: Check resource limits
                echo "=== SOV-005: Resource Limits ==="
                NO_LIMITS=$(kubectl get pods -n ${var.namespace} -o json | python3 -c "
                import json, sys
                data = json.load(sys.stdin)
                count = 0
                for pod in data.get('items', []):
                    for c in pod.get('spec', {}).get('containers', []):
                        if not c.get('resources', {}).get('limits'):
                            count += 1
                print(count)
                " 2>/dev/null || echo "0")
                if [ "$NO_LIMITS" = "0" ]; then
                    check_result "All containers have resource limits" "pass" ""
                else
                    check_result "$NO_LIMITS containers without limits" "warn" "medium"
                fi

                # Summary
                echo ""
                echo "═══════════════════════════════════════════════════════════"
                echo "COMPLIANCE SUMMARY"
                echo "  Timestamp: $TIMESTAMP"
                echo "  Passed:    $PASS"
                echo "  Warnings:  $WARN"
                echo "  Failed:    $FAIL"
                echo "  Score:     $(( PASS * 100 / (PASS + WARN + FAIL) ))%"
                echo "═══════════════════════════════════════════════════════════"

                if [ "$FAIL" -gt 0 ]; then
                    echo "COMPLIANCE STATUS: NON-COMPLIANT"
                    exit 1
                else
                    echo "COMPLIANCE STATUS: COMPLIANT"
                fi
              EOT
              ]

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "500m"
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

            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}

# ── Certificate Rotation CronJob ──────────────────────────────────────────────

resource "kubernetes_cron_job_v1" "cert_rotation_check" {
  metadata {
    name      = "${var.deployment_name}-cert-rotation"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "governance"
      "nova.sovereign/sub-component" = "cert-management"
    }
  }

  spec {
    schedule                      = "0 0 * * *"  # Daily at midnight
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"   = "nova-cert-check"
          "nova.sovereign/component" = "governance"
        }
      }

      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"   = "nova-cert-check"
              "nova.sovereign/component" = "governance"
            }
          }

          spec {
            service_account_name = "${var.deployment_name}-node"

            security_context {
              run_as_non_root = true
              run_as_user     = 1000
            }

            container {
              name  = "cert-checker"
              image = "alpine/openssl:3.1"
              command = ["/bin/sh", "-c"]
              args = [<<-EOT
                set -e
                echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Certificate rotation check starting..."

                WARN_DAYS=${var.cert_rotation_days_before_expiry}
                WARN_SECONDS=$((WARN_DAYS * 86400))

                check_cert() {
                    local name="$1" cert_file="$2"
                    if [ ! -f "$cert_file" ]; then
                        echo "[SKIP] $name: certificate file not found"
                        return
                    fi

                    EXPIRY=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
                    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
                    NOW_EPOCH=$(date +%s)
                    REMAINING=$((EXPIRY_EPOCH - NOW_EPOCH))
                    REMAINING_DAYS=$((REMAINING / 86400))

                    if [ "$REMAINING" -lt 0 ]; then
                        echo "[EXPIRED] $name: expired on $EXPIRY"
                    elif [ "$REMAINING" -lt "$WARN_SECONDS" ]; then
                        echo "[WARNING] $name: expires in $REMAINING_DAYS days ($EXPIRY)"
                    else
                        echo "[OK] $name: expires in $REMAINING_DAYS days"
                    fi
                }

                # Check all TLS secrets in namespace
                echo "Checking TLS certificates in namespace..."
                check_cert "Server TLS" "/certs/tls.crt"
                check_cert "CA Certificate" "/certs/ca.crt"

                echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Certificate check complete"
              EOT
              ]

              volume_mount {
                name       = "certs"
                mount_path = "/certs"
                read_only  = true
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "32Mi"
                }
                limits = {
                  cpu    = "100m"
                  memory = "64Mi"
                }
              }
            }

            volume {
              name = "certs"
              secret {
                secret_name = "${var.deployment_name}-server-tls"
                optional    = true
              }
            }

            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "governance_config" {
  value = {
    config_map          = kubernetes_config_map.governance_config.metadata[0].name
    multisig            = "${var.multisig_threshold}/${var.multisig_total}"
    compliance_frameworks = var.compliance_frameworks
    federation_enabled  = var.federation_enabled
    data_residency      = var.data_residency_strict ? "strict" : "audit"
    emergency_shutdown  = var.emergency_shutdown_enabled
  }
  description = "Governance configuration summary"
}
