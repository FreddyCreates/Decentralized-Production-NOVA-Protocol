# ═══════════════════════════════════════════════════════════════════════════════
# Example: Enterprise Private Cloud (Air-Gapped)
# ═══════════════════════════════════════════════════════════════════════════════

deployment_name      = "nova-sovereign-enterprise"
namespace            = "nova-enterprise"
jurisdiction         = "DE"
classification_level = "unclassified"
cloud_provider       = "private"
replica_count        = 3
enable_airgapped     = true
enable_mtls          = true
backup_retention_days = 90

admin_cidrs = [
  "192.168.0.0/16",
]
