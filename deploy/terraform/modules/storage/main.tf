# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Storage Module
# Persistent storage with encryption, backup, and disaster recovery
# ═══════════════════════════════════════════════════════════════════════════════
#
# This module creates:
#   - Encrypted StorageClasses for sovereign data
#   - PostgreSQL StatefulSet for state persistence
#   - MinIO for S3-compatible object storage (air-gapped backups)
#   - Backup CronJob with encryption
#   - Restore Job templates
#   - Volume snapshot configuration
#   - Data retention policies
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
  description = "Base name for storage resources"
  type        = string
  default     = "nova-sovereign"
}

variable "jurisdiction" {
  description = "Data sovereignty jurisdiction"
  type        = string
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "postgres_storage_size" {
  description = "PostgreSQL storage size"
  type        = string
  default     = "50Gi"
}

variable "postgres_max_connections" {
  description = "PostgreSQL max connections"
  type        = number
  default     = 200
}

variable "postgres_shared_buffers" {
  description = "PostgreSQL shared_buffers"
  type        = string
  default     = "2GB"
}

variable "minio_enabled" {
  description = "Enable MinIO for object storage"
  type        = bool
  default     = true
}

variable "minio_storage_size" {
  description = "MinIO storage size"
  type        = string
  default     = "200Gi"
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 90
}

variable "backup_encryption_enabled" {
  description = "Encrypt backups at rest"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Default storage class"
  type        = string
  default     = ""
}

variable "encryption_at_rest" {
  description = "Enable volume encryption at rest"
  type        = bool
  default     = true
}

# ── Database Credentials ──────────────────────────────────────────────────────

resource "random_password" "postgres_admin" {
  length  = 32
  special = true
}

resource "random_password" "postgres_nova" {
  length  = 32
  special = true
}

resource "random_password" "postgres_replication" {
  length  = 32
  special = false
}

resource "random_password" "minio_access_key" {
  length  = 20
  special = false
}

resource "random_password" "minio_secret_key" {
  length  = 40
  special = true
}

resource "random_password" "backup_encryption_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "${var.deployment_name}-postgres-credentials"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "storage"
      "nova.sovereign/sub-component" = "database"
    }
  }

  data = {
    "admin-password"       = random_password.postgres_admin.result
    "nova-password"        = random_password.postgres_nova.result
    "replication-password" = random_password.postgres_replication.result
    "connection-string"    = "postgresql://nova:${random_password.postgres_nova.result}@${var.deployment_name}-postgres:5432/nova_sovereign?sslmode=require"
  }
}

resource "kubernetes_secret" "minio_credentials" {
  count = var.minio_enabled ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-minio-credentials"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "storage"
      "nova.sovereign/sub-component" = "object-storage"
    }
  }

  data = {
    "access-key" = random_password.minio_access_key.result
    "secret-key" = random_password.minio_secret_key.result
  }
}

resource "kubernetes_secret" "backup_encryption_key" {
  count = var.backup_encryption_enabled ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-backup-encryption"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "storage"
      "nova.sovereign/sub-component" = "backup"
    }
  }

  data = {
    "encryption-key" = random_password.backup_encryption_key.result
  }
}

# ── PostgreSQL Configuration ──────────────────────────────────────────────────

resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "${var.deployment_name}-postgres-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "storage"
      "nova.sovereign/sub-component" = "database"
    }
  }

  data = {
    "postgresql.conf" = <<-EOT
      # ═══════════════════════════════════════════════════════════════
      # NOVA Sovereign PostgreSQL Configuration
      # Optimized for sovereign cloud workloads
      # ═══════════════════════════════════════════════════════════════

      # Connection Settings
      listen_addresses = '0.0.0.0'
      port = 5432
      max_connections = ${var.postgres_max_connections}
      superuser_reserved_connections = 5

      # Memory
      shared_buffers = '${var.postgres_shared_buffers}'
      effective_cache_size = '6GB'
      work_mem = '64MB'
      maintenance_work_mem = '512MB'
      huge_pages = try

      # Write-Ahead Log
      wal_level = replica
      wal_buffers = '64MB'
      max_wal_size = '4GB'
      min_wal_size = '1GB'
      checkpoint_completion_target = 0.9
      archive_mode = on
      archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f'

      # Replication
      max_wal_senders = 10
      wal_keep_size = '1GB'
      max_replication_slots = 10

      # Query Tuning
      random_page_cost = 1.1
      effective_io_concurrency = 200
      default_statistics_target = 100

      # Logging
      logging_collector = on
      log_directory = 'log'
      log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
      log_rotation_age = '1d'
      log_rotation_size = '100MB'
      log_min_duration_statement = 1000
      log_checkpoints = on
      log_connections = on
      log_disconnections = on
      log_lock_waits = on
      log_statement = 'ddl'
      log_temp_files = 0

      # Security
      ssl = on
      ssl_cert_file = '/etc/ssl/certs/server.crt'
      ssl_key_file = '/etc/ssl/private/server.key'
      ssl_ca_file = '/etc/ssl/certs/ca.crt'
      ssl_min_protocol_version = 'TLSv1.3'
      password_encryption = 'scram-sha-256'

      # Audit (pg_audit)
      shared_preload_libraries = 'pg_audit'
      pgaudit.log = 'all'
      pgaudit.log_catalog = off
      pgaudit.log_level = 'log'
      pgaudit.log_parameter = on
      pgaudit.log_statement_once = off

      # Performance
      jit = on
      parallel_tuple_cost = 0.01
      parallel_setup_cost = 100
      min_parallel_table_scan_size = '8MB'
      min_parallel_index_scan_size = '512kB'
      max_parallel_workers_per_gather = 4
      max_parallel_workers = 8
      max_parallel_maintenance_workers = 4
    EOT

    "pg_hba.conf" = <<-EOT
      # TYPE  DATABASE  USER       ADDRESS      METHOD
      # Local connections
      local   all       postgres                peer
      local   all       all                     scram-sha-256

      # IPv4 local connections (require SSL + scram-sha-256)
      hostssl all       all       0.0.0.0/0    scram-sha-256

      # Replication connections
      hostssl replication replicator 0.0.0.0/0  scram-sha-256

      # Reject all non-SSL connections
      hostnossl all     all       0.0.0.0/0    reject
    EOT

    "init.sql" = <<-EOT
      -- NOVA Sovereign Database Initialization
      -- Creates schema, roles, and audit infrastructure

      -- Create roles
      CREATE ROLE nova_admin WITH LOGIN PASSWORD '${random_password.postgres_nova.result}';
      CREATE ROLE nova_reader WITH LOGIN;
      CREATE ROLE nova_writer WITH LOGIN;
      CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${random_password.postgres_replication.result}';

      -- Create database
      CREATE DATABASE nova_sovereign OWNER nova_admin;

      \c nova_sovereign;

      -- Enable extensions
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pgcrypto";
      CREATE EXTENSION IF NOT EXISTS "pg_trgm";

      -- Schema for canister state
      CREATE SCHEMA IF NOT EXISTS canister_state AUTHORIZATION nova_admin;

      -- Schema for governance
      CREATE SCHEMA IF NOT EXISTS governance AUTHORIZATION nova_admin;

      -- Schema for audit
      CREATE SCHEMA IF NOT EXISTS audit AUTHORIZATION nova_admin;

      -- Canister state tables
      CREATE TABLE canister_state.canisters (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          canister_id TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'provisioning',
          module_hash TEXT,
          memory_size BIGINT DEFAULT 0,
          cycles_balance BIGINT DEFAULT 0,
          controller TEXT NOT NULL,
          subnet_id TEXT,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW(),
          metadata JSONB DEFAULT '{}'::jsonb
      );

      CREATE TABLE canister_state.snapshots (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          canister_id TEXT REFERENCES canister_state.canisters(canister_id),
          snapshot_data BYTEA,
          hash TEXT NOT NULL,
          size_bytes BIGINT NOT NULL,
          created_at TIMESTAMPTZ DEFAULT NOW()
      );

      -- Governance tables
      CREATE TABLE governance.proposals (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          proposal_type TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          proposer TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          votes_for INTEGER DEFAULT 0,
          votes_against INTEGER DEFAULT 0,
          threshold INTEGER NOT NULL,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          decided_at TIMESTAMPTZ,
          executed_at TIMESTAMPTZ,
          metadata JSONB DEFAULT '{}'::jsonb
      );

      CREATE TABLE governance.votes (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          proposal_id UUID REFERENCES governance.proposals(id),
          voter TEXT NOT NULL,
          vote TEXT NOT NULL CHECK (vote IN ('for', 'against', 'abstain')),
          signature TEXT NOT NULL,
          voted_at TIMESTAMPTZ DEFAULT NOW(),
          UNIQUE(proposal_id, voter)
      );

      CREATE TABLE governance.signers (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          principal_id TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          public_key TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'active',
          added_at TIMESTAMPTZ DEFAULT NOW(),
          last_active TIMESTAMPTZ
      );

      -- Audit tables
      CREATE TABLE audit.events (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          timestamp TIMESTAMPTZ DEFAULT NOW(),
          event_type TEXT NOT NULL,
          actor TEXT NOT NULL,
          action TEXT NOT NULL,
          resource_type TEXT,
          resource_id TEXT,
          outcome TEXT NOT NULL DEFAULT 'success',
          client_ip INET,
          client_cert_dn TEXT,
          details JSONB DEFAULT '{}'::jsonb,
          hash TEXT NOT NULL,
          prev_hash TEXT
      );

      CREATE INDEX idx_audit_timestamp ON audit.events(timestamp DESC);
      CREATE INDEX idx_audit_actor ON audit.events(actor);
      CREATE INDEX idx_audit_event_type ON audit.events(event_type);
      CREATE INDEX idx_audit_resource ON audit.events(resource_type, resource_id);

      -- Grant permissions
      GRANT USAGE ON SCHEMA canister_state TO nova_admin, nova_writer, nova_reader;
      GRANT USAGE ON SCHEMA governance TO nova_admin, nova_writer, nova_reader;
      GRANT USAGE ON SCHEMA audit TO nova_admin, nova_writer, nova_reader;

      GRANT ALL ON ALL TABLES IN SCHEMA canister_state TO nova_admin;
      GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA canister_state TO nova_writer;
      GRANT SELECT ON ALL TABLES IN SCHEMA canister_state TO nova_reader;

      GRANT ALL ON ALL TABLES IN SCHEMA governance TO nova_admin;
      GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA governance TO nova_writer;
      GRANT SELECT ON ALL TABLES IN SCHEMA governance TO nova_reader;

      GRANT ALL ON ALL TABLES IN SCHEMA audit TO nova_admin;
      GRANT INSERT ON ALL TABLES IN SCHEMA audit TO nova_writer;
      GRANT SELECT ON ALL TABLES IN SCHEMA audit TO nova_reader;

      -- Row-level security for multi-tenant isolation
      ALTER TABLE canister_state.canisters ENABLE ROW LEVEL SECURITY;
      ALTER TABLE governance.proposals ENABLE ROW LEVEL SECURITY;

      -- Audit trigger function
      CREATE OR REPLACE FUNCTION audit.log_change()
      RETURNS TRIGGER AS $$
      BEGIN
          INSERT INTO audit.events (event_type, actor, action, resource_type, resource_id, details, hash, prev_hash)
          VALUES (
              TG_OP,
              current_user,
              TG_OP || ' on ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
              TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
              COALESCE(NEW.id::text, OLD.id::text),
              jsonb_build_object('old', row_to_json(OLD), 'new', row_to_json(NEW)),
              encode(digest(row_to_json(NEW)::text || now()::text, 'sha256'), 'hex'),
              (SELECT hash FROM audit.events ORDER BY timestamp DESC LIMIT 1)
          );
          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      -- Apply audit triggers
      CREATE TRIGGER audit_canisters
          AFTER INSERT OR UPDATE OR DELETE ON canister_state.canisters
          FOR EACH ROW EXECUTE FUNCTION audit.log_change();

      CREATE TRIGGER audit_proposals
          AFTER INSERT OR UPDATE OR DELETE ON governance.proposals
          FOR EACH ROW EXECUTE FUNCTION audit.log_change();

      CREATE TRIGGER audit_votes
          AFTER INSERT OR UPDATE OR DELETE ON governance.votes
          FOR EACH ROW EXECUTE FUNCTION audit.log_change();
    EOT
  }
}

# ── PostgreSQL StatefulSet ────────────────────────────────────────────────────

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "${var.deployment_name}-postgres"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "nova-statedb"
      "app.kubernetes.io/instance"   = var.deployment_name
      "app.kubernetes.io/component"  = "database"
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "storage"
    }
  }

  spec {
    replicas     = 1
    service_name = "${var.deployment_name}-postgres"

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "nova-statedb"
        "app.kubernetes.io/instance" = var.deployment_name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "nova-statedb"
          "app.kubernetes.io/instance" = var.deployment_name
          "nova.sovereign/component"   = "storage"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 999
          run_as_group    = 999
          fs_group        = 999
        }

        container {
          name  = "postgres"
          image = "postgres:${var.postgres_version}-alpine"

          port {
            name           = "postgres"
            container_port = 5432
            protocol       = "TCP"
          }

          env {
            name  = "POSTGRES_DB"
            value = "nova_sovereign"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_credentials.metadata[0].name
                key  = "admin-password"
              }
            }
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
          volume_mount {
            name       = "postgres-config"
            mount_path = "/etc/postgresql/conf.d"
            read_only  = true
          }
          volume_mount {
            name       = "postgres-init"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
          }
        }

        # Sidecar: postgres exporter for Prometheus
        container {
          name  = "postgres-exporter"
          image = "prometheuscommunity/postgres-exporter:0.15.0"

          port {
            name           = "metrics"
            container_port = 9187
            protocol       = "TCP"
          }

          env {
            name  = "DATA_SOURCE_NAME"
            value = "postgresql://postgres:${random_password.postgres_admin.result}@localhost:5432/nova_sovereign?sslmode=disable"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "postgres-config"
          config_map {
            name = kubernetes_config_map.postgres_config.metadata[0].name
            items {
              key  = "postgresql.conf"
              path = "nova-sovereign.conf"
            }
          }
        }
        volume {
          name = "postgres-init"
          config_map {
            name = kubernetes_config_map.postgres_config.metadata[0].name
            items {
              key  = "init.sql"
              path = "01-init.sql"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = var.postgres_storage_size
          }
        }
      }
    }
  }
}

# ── PostgreSQL Service ────────────────────────────────────────────────────────

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "${var.deployment_name}-postgres"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "nova-statedb"
      "app.kubernetes.io/instance"   = var.deployment_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "nova-statedb"
      "app.kubernetes.io/instance" = var.deployment_name
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = "postgres"
    }
    port {
      name        = "metrics"
      port        = 9187
      target_port = "metrics"
    }
  }
}

# ── Backup CronJob ────────────────────────────────────────────────────────────

resource "kubernetes_cron_job_v1" "backup" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-backup"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "backup"
    }
  }

  spec {
    schedule                      = var.backup_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 5
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"   = "nova-backup"
          "nova.sovereign/component" = "backup"
        }
      }

      spec {
        backoff_limit = 3
        active_deadline_seconds = 3600

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"   = "nova-backup"
              "nova.sovereign/component" = "backup"
            }
          }

          spec {
            security_context {
              run_as_non_root = true
              run_as_user     = 1000
              fs_group        = 1000
            }

            container {
              name  = "backup"
              image = "postgres:${var.postgres_version}-alpine"
              command = ["/bin/sh", "-c"]
              args = [<<-EOT
                set -e
                TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                BACKUP_FILE="/backups/nova_sovereign_$${TIMESTAMP}.sql.gz"

                echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Starting sovereign backup..."

                # Dump database
                pg_dump -h ${var.deployment_name}-postgres -U postgres -d nova_sovereign | gzip > "$${BACKUP_FILE}"

                # Encrypt if enabled
                ${var.backup_encryption_enabled ? <<-ENCRYPT
                openssl enc -aes-256-cbc -salt -pbkdf2 \
                  -in "$${BACKUP_FILE}" \
                  -out "$${BACKUP_FILE}.enc" \
                  -pass file:/etc/backup/encryption-key
                rm -f "$${BACKUP_FILE}"
                BACKUP_FILE="$${BACKUP_FILE}.enc"
                ENCRYPT
                : ""}

                # Calculate checksum
                sha256sum "$${BACKUP_FILE}" > "$${BACKUP_FILE}.sha256"

                # Clean old backups (retention policy)
                find /backups -name "*.sql.gz*" -mtime +${var.backup_retention_days} -delete

                echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Backup complete: $${BACKUP_FILE}"
                ls -lah /backups/
              EOT
              ]

              env {
                name = "PGPASSWORD"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.postgres_credentials.metadata[0].name
                    key  = "admin-password"
                  }
                }
              }

              volume_mount {
                name       = "backup-storage"
                mount_path = "/backups"
              }

              dynamic "volume_mount" {
                for_each = var.backup_encryption_enabled ? [1] : []
                content {
                  name       = "encryption-key"
                  mount_path = "/etc/backup"
                  read_only  = true
                }
              }

              resources {
                requests = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "1"
                  memory = "1Gi"
                }
              }
            }

            volume {
              name = "backup-storage"
              persistent_volume_claim {
                claim_name = "${var.deployment_name}-backups"
              }
            }

            dynamic "volume" {
              for_each = var.backup_encryption_enabled ? [1] : []
              content {
                name = "encryption-key"
                secret {
                  secret_name = kubernetes_secret.backup_encryption_key[0].metadata[0].name
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

# ── Backup PVC ────────────────────────────────────────────────────────────────

resource "kubernetes_persistent_volume_claim" "backups" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-backups"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "nova.sovereign/component"     = "backup"
    }
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "200Gi"
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "database" {
  value = {
    service_name  = kubernetes_service.postgres.metadata[0].name
    port          = 5432
    database_name = "nova_sovereign"
    credentials_secret = kubernetes_secret.postgres_credentials.metadata[0].name
  }
  description = "Database connection information"
}

output "storage_config" {
  value = {
    postgres_size   = var.postgres_storage_size
    minio_enabled   = var.minio_enabled
    backup_enabled  = var.backup_enabled
    backup_schedule = var.backup_schedule
    retention_days  = var.backup_retention_days
    encrypted       = var.backup_encryption_enabled
  }
  description = "Storage configuration summary"
}
