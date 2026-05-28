# ═══════════════════════════════════════════════════════════════════════════════
# Example: US Government Deployment (GovCloud)
# ═══════════════════════════════════════════════════════════════════════════════

deployment_name      = "nova-sovereign-usgov"
namespace            = "nova-sovereign"
jurisdiction         = "US"
classification_level = "cui"
cloud_provider       = "aws-govcloud"
replica_count        = 5
enable_airgapped     = false
enable_mtls          = true
backup_retention_days = 365

admin_cidrs = [
  "10.0.0.0/8",
  "172.16.0.0/12",
]
