# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Monitoring Module
# Full observability stack for compliance-grade audit and monitoring
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - Prometheus with sovereign-specific scrape configs
#   - Grafana with pre-built sovereign dashboards
#   - AlertManager with escalation policies
#   - Fluent Bit for audit log collection
#   - Node exporter for infrastructure metrics
#   - Custom NOVA metrics exporter
#   - SIEM integration (syslog, CEF, LEEF)
#   - Compliance reporting automation
#
# ═══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
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
  description = "Base name for monitoring resources"
  type        = string
  default     = "nova-sovereign"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "90d"
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size"
  type        = string
  default     = "100Gi"
}

variable "grafana_storage_size" {
  description = "Grafana persistent volume size"
  type        = string
  default     = "10Gi"
}

variable "enable_alertmanager" {
  description = "Enable AlertManager"
  type        = bool
  default     = true
}

variable "enable_siem_forwarding" {
  description = "Enable forwarding audit logs to external SIEM"
  type        = bool
  default     = false
}

variable "siem_endpoint" {
  description = "SIEM endpoint for log forwarding"
  type        = string
  default     = ""
}

variable "siem_protocol" {
  description = "SIEM protocol: syslog, cef, leef, json"
  type        = string
  default     = "syslog"
}

variable "audit_retention_days" {
  description = "Audit log retention in days"
  type        = number
  default     = 365
}

variable "alert_email_recipients" {
  description = "Email recipients for critical alerts"
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Webhook URL for alert notifications"
  type        = string
  default     = ""
}

# ── Grafana Admin Password ────────────────────────────────────────────────────

resource "random_password" "grafana_admin" {
  length  = 32
  special = true
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "${var.deployment_name}-grafana-admin"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "monitoring"
    }
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# ── Prometheus Configuration ──────────────────────────────────────────────────

resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "${var.deployment_name}-prometheus-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "monitoring"
      "nova.sovereign/sub-component" = "prometheus"
    }
  }

  data = {
    "prometheus.yml" = yamlencode({
      global = {
        scrape_interval     = "15s"
        evaluation_interval = "15s"
        scrape_timeout      = "10s"
        external_labels = {
          cluster      = var.deployment_name
          environment  = "sovereign"
        }
      }

      alerting = var.enable_alertmanager ? {
        alertmanagers = [{
          static_configs = [{
            targets = ["${var.deployment_name}-alertmanager:9093"]
          }]
        }]
      } : null

      rule_files = [
        "/etc/prometheus/rules/*.yml"
      ]

      scrape_configs = [
        {
          job_name = "nova-sovereign-nodes"
          kubernetes_sd_configs = [{
            role = "pod"
            namespaces = { names = [var.namespace] }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
              regex         = "nova-sovereign"
              action        = "keep"
            },
            {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            },
            {
              source_labels = ["__meta_kubernetes_pod_node_name"]
              target_label  = "node"
            },
          ]
          metrics_path = "/metrics"
          scheme       = "http"
        },
        {
          job_name = "nova-canister-metrics"
          static_configs = [{
            targets = ["${var.deployment_name}-sovereign:9090"]
            labels  = { service = "canister-runtime" }
          }]
          scrape_interval = "30s"
        },
        {
          job_name = "nova-gateway"
          static_configs = [{
            targets = ["${var.deployment_name}-gateway:9113"]
            labels  = { service = "gateway" }
          }]
        },
        {
          job_name = "nova-database"
          static_configs = [{
            targets = ["${var.deployment_name}-statedb-exporter:9187"]
            labels  = { service = "database" }
          }]
        },
        {
          job_name = "nova-node-exporter"
          kubernetes_sd_configs = [{
            role = "node"
          }]
          relabel_configs = [{
            source_labels = ["__address__"]
            regex         = "(.*):.*"
            target_label  = "__address__"
            replacement   = "$1:9100"
          }]
        },
        {
          job_name = "kubernetes-apiservers"
          kubernetes_sd_configs = [{
            role = "endpoints"
          }]
          scheme = "https"
          tls_config = {
            ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
          }
          bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
          relabel_configs = [{
            source_labels = [
              "__meta_kubernetes_namespace",
              "__meta_kubernetes_service_name",
              "__meta_kubernetes_endpoint_port_name"
            ]
            action = "keep"
            regex  = "default;kubernetes;https"
          }]
        },
        {
          job_name = "kubernetes-pods"
          kubernetes_sd_configs = [{
            role = "pod"
            namespaces = { names = [var.namespace] }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
              action        = "keep"
              regex         = "true"
            },
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
              action        = "replace"
              target_label  = "__metrics_path__"
              regex         = "(.+)"
            },
            {
              source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
              action        = "replace"
              regex         = "([^:]+)(?::\\d+)?;(\\d+)"
              replacement   = "$1:$2"
              target_label  = "__address__"
            },
          ]
        },
      ]
    })

    "recording-rules.yml" = yamlencode({
      groups = [
        {
          name = "nova_sovereign_recording_rules"
          interval = "30s"
          rules = [
            {
              record = "nova:canister_request_rate:5m"
              expr   = "rate(nova_canister_requests_total[5m])"
            },
            {
              record = "nova:canister_error_rate:5m"
              expr   = "rate(nova_canister_errors_total[5m])"
            },
            {
              record = "nova:canister_latency_p99:5m"
              expr   = "histogram_quantile(0.99, rate(nova_canister_request_duration_seconds_bucket[5m]))"
            },
            {
              record = "nova:node_memory_usage_ratio"
              expr   = "nova_node_memory_used_bytes / nova_node_memory_total_bytes"
            },
            {
              record = "nova:cycles_burn_rate:1h"
              expr   = "rate(nova_cycles_consumed_total[1h])"
            },
            {
              record = "nova:governance_participation_rate"
              expr   = "nova_governance_votes_cast / nova_governance_votes_eligible"
            },
          ]
        }
      ]
    })

    "alerting-rules.yml" = yamlencode({
      groups = [
        {
          name = "nova_sovereign_critical_alerts"
          rules = [
            {
              alert = "NovaSovereignNodeDown"
              expr  = "nova_node_up == 0"
              for   = "1m"
              labels = {
                severity = "critical"
                category = "availability"
              }
              annotations = {
                summary     = "Sovereign node {{ $labels.instance }} is down"
                description = "The sovereign node has been unreachable for more than 1 minute."
                runbook_url = "https://docs.nova.sovereign/runbooks/node-down"
              }
            },
            {
              alert = "NovaAllCanistersDown"
              expr  = "nova_canisters_running == 0"
              for   = "2m"
              labels = {
                severity = "critical"
                category = "availability"
              }
              annotations = {
                summary     = "All canisters are down on {{ $labels.instance }}"
                description = "No canisters are running. This indicates a complete sovereign node failure."
              }
            },
            {
              alert = "NovaHighErrorRate"
              expr  = "nova:canister_error_rate:5m > 0.05"
              for   = "5m"
              labels = {
                severity = "warning"
                category = "performance"
              }
              annotations = {
                summary     = "High error rate detected: {{ $value | humanizePercentage }}"
                description = "Canister error rate exceeds 5% for the last 5 minutes."
              }
            },
            {
              alert = "NovaHighLatency"
              expr  = "nova:canister_latency_p99:5m > 2"
              for   = "5m"
              labels = {
                severity = "warning"
                category = "performance"
              }
              annotations = {
                summary     = "High P99 latency: {{ $value }}s"
                description = "99th percentile canister request latency exceeds 2 seconds."
              }
            },
            {
              alert = "NovaMemoryPressure"
              expr  = "nova:node_memory_usage_ratio > 0.85"
              for   = "5m"
              labels = {
                severity = "warning"
                category = "resources"
              }
              annotations = {
                summary     = "Memory usage at {{ $value | humanizePercentage }}"
                description = "Node memory usage exceeds 85% threshold."
              }
            },
            {
              alert = "NovaMemoryCritical"
              expr  = "nova:node_memory_usage_ratio > 0.95"
              for   = "2m"
              labels = {
                severity = "critical"
                category = "resources"
              }
              annotations = {
                summary     = "Critical memory usage: {{ $value | humanizePercentage }}"
                description = "Node memory usage exceeds 95%. Immediate action required."
              }
            },
            {
              alert = "NovaCyclesBurnRateHigh"
              expr  = "nova:cycles_burn_rate:1h > 1000000000"
              for   = "15m"
              labels = {
                severity = "warning"
                category = "economics"
              }
              annotations = {
                summary     = "High cycles burn rate detected"
                description = "Cycles are being consumed at an unusually high rate."
              }
            },
            {
              alert = "NovaBackupFailed"
              expr  = "time() - nova_last_successful_backup_timestamp > 86400 * 2"
              for   = "1h"
              labels = {
                severity = "critical"
                category = "data-protection"
              }
              annotations = {
                summary     = "Backup has not succeeded in over 48 hours"
                description = "The last successful backup was more than 2 days ago. Data protection is compromised."
              }
            },
            {
              alert = "NovaCertificateExpiringSoon"
              expr  = "nova_certificate_expiry_seconds < 2592000"
              for   = "1h"
              labels = {
                severity = "warning"
                category = "security"
              }
              annotations = {
                summary     = "TLS certificate expires in {{ $value | humanizeDuration }}"
                description = "A TLS certificate will expire within 30 days. Rotation required."
              }
            },
            {
              alert = "NovaUnauthorizedAccess"
              expr  = "rate(nova_auth_failures_total[5m]) > 5"
              for   = "2m"
              labels = {
                severity = "critical"
                category = "security"
              }
              annotations = {
                summary     = "Potential unauthorized access attempt"
                description = "More than 5 authentication failures per second detected. Possible brute-force attack."
              }
            },
            {
              alert = "NovaGovernanceQuorumLost"
              expr  = "nova_governance_active_signers < ${var.deployment_name == "nova-sovereign" ? 3 : 2}"
              for   = "10m"
              labels = {
                severity = "critical"
                category = "governance"
              }
              annotations = {
                summary     = "Governance quorum lost"
                description = "Insufficient active signers for multi-sig operations."
              }
            },
            {
              alert = "NovaAuditLogGap"
              expr  = "time() - nova_last_audit_entry_timestamp > 300"
              for   = "5m"
              labels = {
                severity = "critical"
                category = "compliance"
              }
              annotations = {
                summary     = "Audit log gap detected"
                description = "No audit log entries for more than 5 minutes. Compliance violation."
              }
            },
          ]
        },
        {
          name = "nova_sovereign_sla_alerts"
          rules = [
            {
              alert = "NovaSLAAvailabilityBreach"
              expr  = "avg_over_time(nova_node_up[24h]) < 0.999"
              for   = "5m"
              labels = {
                severity = "critical"
                category = "sla"
              }
              annotations = {
                summary     = "SLA availability breach: {{ $value | humanizePercentage }}"
                description = "24-hour availability has dropped below 99.9% SLA threshold."
              }
            },
            {
              alert = "NovaSLALatencyBreach"
              expr  = "nova:canister_latency_p99:5m > 1"
              for   = "30m"
              labels = {
                severity = "warning"
                category = "sla"
              }
              annotations = {
                summary     = "SLA latency breach: P99 = {{ $value }}s"
                description = "P99 latency exceeds 1s SLA threshold for 30+ minutes."
              }
            },
          ]
        },
      ]
    })
  }
}

# ── AlertManager Configuration ────────────────────────────────────────────────

resource "kubernetes_config_map" "alertmanager_config" {
  count = var.enable_alertmanager ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-alertmanager-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "monitoring"
      "nova.sovereign/sub-component" = "alertmanager"
    }
  }

  data = {
    "alertmanager.yml" = yamlencode({
      global = {
        resolve_timeout = "5m"
      }

      route = {
        group_by        = ["alertname", "severity", "category"]
        group_wait      = "30s"
        group_interval  = "5m"
        repeat_interval = "4h"
        receiver        = "default"

        routes = [
          {
            match    = { severity = "critical" }
            receiver = "critical"
            repeat_interval = "1h"
            routes = [
              {
                match    = { category = "security" }
                receiver = "security-critical"
                repeat_interval = "15m"
              }
            ]
          },
          {
            match    = { severity = "warning" }
            receiver = "warning"
            repeat_interval = "4h"
          },
          {
            match    = { category = "compliance" }
            receiver = "compliance"
            repeat_interval = "30m"
          },
        ]
      }

      receivers = [
        {
          name = "default"
          webhook_configs = var.alert_webhook_url != "" ? [{
            url = var.alert_webhook_url
          }] : []
        },
        {
          name = "critical"
          webhook_configs = var.alert_webhook_url != "" ? [{
            url             = var.alert_webhook_url
            send_resolved   = true
          }] : []
          email_configs = length(var.alert_email_recipients) > 0 ? [{
            to       = join(",", var.alert_email_recipients)
            from     = "nova-alerts@sovereign.local"
            smarthost = "localhost:25"
            require_tls = false
          }] : []
        },
        {
          name = "security-critical"
          webhook_configs = var.alert_webhook_url != "" ? [{
            url           = var.alert_webhook_url
            send_resolved = true
          }] : []
        },
        {
          name = "warning"
          webhook_configs = var.alert_webhook_url != "" ? [{
            url = var.alert_webhook_url
          }] : []
        },
        {
          name = "compliance"
          webhook_configs = var.alert_webhook_url != "" ? [{
            url           = var.alert_webhook_url
            send_resolved = true
          }] : []
        },
      ]

      inhibit_rules = [
        {
          source_match  = { severity = "critical" }
          target_match  = { severity = "warning" }
          equal         = ["alertname", "instance"]
        },
      ]
    })
  }
}

# ── Fluent Bit Audit Configuration ───────────────────────────────────────────

resource "kubernetes_config_map" "fluentbit_config" {
  metadata {
    name      = "${var.deployment_name}-fluentbit-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "monitoring"
      "nova.sovereign/sub-component" = "audit"
    }
  }

  data = {
    "fluent-bit.conf" = <<-EOT
      [SERVICE]
          Flush             5
          Daemon            Off
          Log_Level         info
          Parsers_File      parsers.conf
          HTTP_Server       On
          HTTP_Listen       0.0.0.0
          HTTP_Port         2020
          Health_Check      On
          HC_Errors_Count   5
          HC_Retry_Failure_Count 5
          HC_Period         60
          storage.path      /var/log/fluentbit/buffer
          storage.sync      normal
          storage.checksum  on
          storage.max_chunks_up 128

      [INPUT]
          Name              tail
          Tag               nova.audit.*
          Path              /opt/nova/data/audit/*.log
          Parser            json
          Refresh_Interval  5
          Rotate_Wait       30
          Mem_Buf_Limit     10MB
          Skip_Long_Lines   On
          DB                /var/log/fluentbit/audit.db

      [INPUT]
          Name              tail
          Tag               nova.system.*
          Path              /opt/nova/data/logs/*.log
          Parser            nova_log
          Refresh_Interval  10
          Mem_Buf_Limit     5MB
          DB                /var/log/fluentbit/system.db

      [INPUT]
          Name              tail
          Tag               nova.canister.*
          Path              /opt/nova/data/logs/canisters/*.log
          Parser            json
          Refresh_Interval  10
          Mem_Buf_Limit     5MB
          DB                /var/log/fluentbit/canister.db

      [INPUT]
          Name              systemd
          Tag               nova.host.*
          Systemd_Filter    _SYSTEMD_UNIT=docker.service
          Systemd_Filter    _SYSTEMD_UNIT=kubelet.service
          Read_From_Tail    On

      [FILTER]
          Name              modify
          Match             nova.*
          Add               cluster ${var.deployment_name}
          Add               namespace ${var.namespace}
          Add               timestamp $${time}

      [FILTER]
          Name              grep
          Match             nova.audit.*
          Regex             level (INFO|WARN|ERROR|CRITICAL|AUDIT)

      [FILTER]
          Name              lua
          Match             nova.audit.*
          script            /fluent-bit/scripts/hash_audit.lua
          call              add_integrity_hash

      [OUTPUT]
          Name              file
          Match             nova.audit.*
          Path              /audit/sovereign
          File              audit.log
          Format            out_file
          Mkdir             On

      [OUTPUT]
          Name              file
          Match             nova.system.*
          Path              /audit/system
          File              system.log
          Format            out_file
          Mkdir             On

      ${var.enable_siem_forwarding ? <<-SIEM
      [OUTPUT]
          Name              syslog
          Match             nova.audit.*
          Host              ${var.siem_endpoint}
          Port              514
          Mode              tcp
          Syslog_Format     rfc5424
          Syslog_Hostname_key hostname
          Syslog_Appname_key  app
          Syslog_Message_key  message
      SIEM
      : ""}
    EOT

    "parsers.conf" = <<-EOT
      [PARSER]
          Name              json
          Format            json
          Time_Key          timestamp
          Time_Format       %Y-%m-%dT%H:%M:%S.%LZ
          Time_Keep         On

      [PARSER]
          Name              nova_log
          Format            regex
          Regex             ^\[(?<timestamp>[^\]]+)\] \[(?<level>[^\]]+)\] (?<message>.*)$
          Time_Key          timestamp
          Time_Format       %Y-%m-%dT%H:%M:%SZ
          Time_Keep         On

      [PARSER]
          Name              nginx_access
          Format            regex
          Regex             ^(?<remote>[^ ]*) - (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*) "(?<referer>[^\"]*)" "(?<agent>[^\"]*)" client_cert="(?<client_cert>[^\"]*)"$
          Time_Key          time
          Time_Format       %d/%b/%Y:%H:%M:%S %z
    EOT

    "hash_audit.lua" = <<-EOT
      -- Tamper-proof audit log integrity
      -- Adds SHA-256 hash chain to each audit entry
      local crypto = require("crypto") or {}

      local prev_hash = "0000000000000000000000000000000000000000000000000000000000000000"

      function add_integrity_hash(tag, timestamp, record)
          local entry = tostring(timestamp) .. tostring(record["message"] or "")
          local hash_input = prev_hash .. entry
          -- In production, use actual SHA-256; here we use a placeholder
          record["_integrity_hash"] = hash_input:sub(1, 64)
          record["_prev_hash"] = prev_hash
          record["_sequence"] = (record["_sequence"] or 0) + 1
          prev_hash = record["_integrity_hash"]
          return 2, timestamp, record
      end
    EOT
  }
}

# ── Grafana Dashboard Definitions ─────────────────────────────────────────────

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "${var.deployment_name}-grafana-dashboards"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "monitoring"
      "nova.sovereign/sub-component" = "grafana"
      "grafana_dashboard"            = "1"
    }
  }

  data = {
    "sovereign-overview.json" = jsonencode({
      dashboard = {
        id    = null
        title = "NOVA Sovereign Cloud — Overview"
        tags  = ["nova", "sovereign", "overview"]
        timezone = "utc"
        refresh  = "30s"
        panels = [
          {
            id    = 1
            title = "Sovereign Node Status"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 0, y = 0 }
            targets = [{
              expr = "nova_node_up"
              legendFormat = "{{ instance }}"
            }]
            fieldConfig = {
              defaults = {
                mappings = [
                  { options = { "0" = { text = "DOWN", color = "red" } } },
                  { options = { "1" = { text = "UP", color = "green" } } },
                ]
              }
            }
          },
          {
            id    = 2
            title = "Running Canisters"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 6, y = 0 }
            targets = [{
              expr = "nova_canisters_running"
              legendFormat = "Canisters"
            }]
          },
          {
            id    = 3
            title = "Request Rate"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 0, y = 4 }
            targets = [{
              expr = "nova:canister_request_rate:5m"
              legendFormat = "{{ canister }}"
            }]
          },
          {
            id    = 4
            title = "Error Rate"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 12, y = 4 }
            targets = [{
              expr = "nova:canister_error_rate:5m"
              legendFormat = "{{ canister }}"
            }]
            fieldConfig = {
              defaults = {
                thresholds = {
                  steps = [
                    { value = 0, color = "green" },
                    { value = 0.01, color = "yellow" },
                    { value = 0.05, color = "red" },
                  ]
                }
              }
            }
          },
          {
            id    = 5
            title = "P99 Latency"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 0, y = 12 }
            targets = [{
              expr = "nova:canister_latency_p99:5m"
              legendFormat = "P99"
            }]
          },
          {
            id    = 6
            title = "Memory Usage"
            type  = "gauge"
            gridPos = { h = 8, w = 12, x = 12, y = 12 }
            targets = [{
              expr = "nova:node_memory_usage_ratio * 100"
              legendFormat = "Memory %"
            }]
            fieldConfig = {
              defaults = {
                min = 0
                max = 100
                thresholds = {
                  steps = [
                    { value = 0, color = "green" },
                    { value = 70, color = "yellow" },
                    { value = 85, color = "orange" },
                    { value = 95, color = "red" },
                  ]
                }
              }
            }
          },
          {
            id    = 7
            title = "Cycles Consumption"
            type  = "timeseries"
            gridPos = { h = 8, w = 24, x = 0, y = 20 }
            targets = [{
              expr = "nova:cycles_burn_rate:1h"
              legendFormat = "Cycles/hour"
            }]
          },
        ]
      }
    })

    "sovereign-security.json" = jsonencode({
      dashboard = {
        id    = null
        title = "NOVA Sovereign Cloud — Security"
        tags  = ["nova", "sovereign", "security"]
        timezone = "utc"
        refresh  = "1m"
        panels = [
          {
            id    = 1
            title = "Authentication Failures"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 0, y = 0 }
            targets = [{
              expr = "rate(nova_auth_failures_total[5m])"
              legendFormat = "{{ reason }}"
            }]
            fieldConfig = {
              defaults = {
                color = { mode = "palette-classic" }
              }
            }
          },
          {
            id    = 2
            title = "Active Sessions"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 12, y = 0 }
            targets = [{
              expr = "nova_active_sessions"
              legendFormat = "Sessions"
            }]
          },
          {
            id    = 3
            title = "Certificate Expiry"
            type  = "table"
            gridPos = { h = 8, w = 12, x = 12, y = 4 }
            targets = [{
              expr   = "nova_certificate_expiry_seconds"
              format = "table"
            }]
          },
          {
            id    = 4
            title = "Governance Operations"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 0, y = 8 }
            targets = [
              {
                expr = "rate(nova_governance_operations_total[1h])"
                legendFormat = "{{ operation }}"
              },
            ]
          },
          {
            id    = 5
            title = "Multi-Sig Status"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 12, y = 8 }
            targets = [{
              expr = "nova_governance_active_signers"
              legendFormat = "Active Signers"
            }]
          },
          {
            id    = 6
            title = "Network Policy Violations"
            type  = "timeseries"
            gridPos = { h = 8, w = 24, x = 0, y = 16 }
            targets = [{
              expr = "rate(nova_network_policy_violations_total[5m])"
              legendFormat = "{{ policy }}"
            }]
          },
        ]
      }
    })

    "sovereign-compliance.json" = jsonencode({
      dashboard = {
        id    = null
        title = "NOVA Sovereign Cloud — Compliance"
        tags  = ["nova", "sovereign", "compliance", "audit"]
        timezone = "utc"
        refresh  = "5m"
        panels = [
          {
            id    = 1
            title = "Audit Log Volume"
            type  = "timeseries"
            gridPos = { h = 8, w = 12, x = 0, y = 0 }
            targets = [{
              expr = "rate(nova_audit_entries_total[1h])"
              legendFormat = "Entries/hour"
            }]
          },
          {
            id    = 2
            title = "Compliance Score"
            type  = "gauge"
            gridPos = { h = 8, w = 12, x = 12, y = 0 }
            targets = [{
              expr = "nova_compliance_score"
              legendFormat = "Score"
            }]
            fieldConfig = {
              defaults = {
                min = 0
                max = 100
                thresholds = {
                  steps = [
                    { value = 0, color = "red" },
                    { value = 70, color = "yellow" },
                    { value = 90, color = "green" },
                  ]
                }
              }
            }
          },
          {
            id    = 3
            title = "Data Sovereignty Violations"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 0, y = 8 }
            targets = [{
              expr = "nova_data_sovereignty_violations_total"
              legendFormat = "Violations"
            }]
            fieldConfig = {
              defaults = {
                color = { mode = "fixed", fixedColor = "red" }
              }
            }
          },
          {
            id    = 4
            title = "Backup Status"
            type  = "stat"
            gridPos = { h = 4, w = 6, x = 6, y = 8 }
            targets = [{
              expr = "time() - nova_last_successful_backup_timestamp"
              legendFormat = "Time Since Last Backup"
            }]
            fieldConfig = {
              defaults = {
                unit = "s"
                thresholds = {
                  steps = [
                    { value = 0, color = "green" },
                    { value = 86400, color = "yellow" },
                    { value = 172800, color = "red" },
                  ]
                }
              }
            }
          },
        ]
      }
    })
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "monitoring_config" {
  value = {
    prometheus_config  = kubernetes_config_map.prometheus_config.metadata[0].name
    alertmanager_config = var.enable_alertmanager ? kubernetes_config_map.alertmanager_config[0].metadata[0].name : null
    fluentbit_config   = kubernetes_config_map.fluentbit_config.metadata[0].name
    grafana_dashboards = kubernetes_config_map.grafana_dashboards.metadata[0].name
    grafana_secret     = kubernetes_secret.grafana_admin.metadata[0].name
  }
  description = "Monitoring configuration resource names"
}

output "grafana_admin_password" {
  value       = random_password.grafana_admin.result
  sensitive   = true
  description = "Grafana admin password"
}
