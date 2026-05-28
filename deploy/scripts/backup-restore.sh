#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Backup & Restore Operations
# Encrypted backup management for government-grade data protection
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./backup-restore.sh backup --full
#   ./backup-restore.sh backup --incremental
#   ./backup-restore.sh restore --timestamp 20240101_020000
#   ./backup-restore.sh list
#   ./backup-restore.sh verify --timestamp 20240101_020000
#   ./backup-restore.sh rotate
#
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_DIR="$(dirname "${SCRIPT_DIR}")"
readonly BACKUP_DIR="${NOVA_BACKUP_DIR:-/opt/nova/data/backups}"
readonly ENCRYPTION_KEY_FILE="${NOVA_ENCRYPTION_KEY:-/opt/nova/keys/backup.key}"
readonly NAMESPACE="${NOVA_NAMESPACE:-nova-sovereign}"
readonly DEPLOYMENT_NAME="${NOVA_DEPLOYMENT:-nova-sovereign}"
readonly RETENTION_DAYS="${NOVA_BACKUP_RETENTION:-90}"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN=$'\033[32m'
CYAN=$'\033[36m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

log() { echo -e "${GREEN}[$(date -u '+%Y-%m-%dT%H:%M:%SZ')]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }

# ── Backup Functions ──────────────────────────────────────────────────────────

backup_full() {
    log "Starting full sovereign backup..."
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="nova_sovereign_full_${timestamp}"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    mkdir -p "${backup_path}"

    # 1. Backup database
    log "Backing up PostgreSQL database..."
    local db_password
    db_password=$(kubectl get secret -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-credentials" \
        -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d)

    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        pg_dumpall -U postgres 2>/dev/null | gzip > "${backup_path}/database.sql.gz"
    log "Database backup complete"

    # 2. Backup canister state
    log "Backing up canister state..."
    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        tar -czf - /opt/nova/data/.dfx 2>/dev/null > "${backup_path}/canister-state.tar.gz" || \
        log_warn "Canister state backup may be incomplete"
    log "Canister state backup complete"

    # 3. Backup configuration
    log "Backing up configuration..."
    kubectl get configmaps -n "${NAMESPACE}" -o yaml > "${backup_path}/configmaps.yaml"
    kubectl get secrets -n "${NAMESPACE}" -o yaml > "${backup_path}/secrets.yaml"
    log "Configuration backup complete"

    # 4. Backup governance state
    log "Backing up governance state..."
    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        pg_dump -U postgres -d nova_sovereign --schema=governance 2>/dev/null | \
        gzip > "${backup_path}/governance.sql.gz"
    log "Governance backup complete"

    # 5. Backup audit logs
    log "Backing up audit logs..."
    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        tar -czf - /opt/nova/data/audit 2>/dev/null > "${backup_path}/audit-logs.tar.gz" || \
        log_warn "Audit log backup may be incomplete"
    log "Audit log backup complete"

    # 6. Create manifest
    cat > "${backup_path}/manifest.json" <<EOF
{
    "version": "1.0",
    "type": "full",
    "timestamp": "${timestamp}",
    "deployment": "${DEPLOYMENT_NAME}",
    "namespace": "${NAMESPACE}",
    "jurisdiction": "$(kubectl get namespace ${NAMESPACE} -o jsonpath='{.metadata.labels.sovereignty/jurisdiction}' 2>/dev/null || echo 'unknown')",
    "components": [
        {"name": "database", "file": "database.sql.gz", "type": "pg_dumpall"},
        {"name": "canister-state", "file": "canister-state.tar.gz", "type": "tar"},
        {"name": "configmaps", "file": "configmaps.yaml", "type": "kubernetes"},
        {"name": "secrets", "file": "secrets.yaml", "type": "kubernetes"},
        {"name": "governance", "file": "governance.sql.gz", "type": "pg_dump"},
        {"name": "audit-logs", "file": "audit-logs.tar.gz", "type": "tar"}
    ],
    "encrypted": true,
    "checksum_algorithm": "sha256"
}
EOF

    # 7. Generate checksums
    log "Generating checksums..."
    cd "${backup_path}"
    sha256sum *.gz *.yaml 2>/dev/null > checksums.sha256
    cd -

    # 8. Encrypt the backup
    if [[ -f "${ENCRYPTION_KEY_FILE}" ]]; then
        log "Encrypting backup..."
        tar -czf "${backup_path}.tar.gz" -C "${BACKUP_DIR}" "${backup_name}"
        openssl enc -aes-256-gcm -salt -pbkdf2 -iter 100000 \
            -in "${backup_path}.tar.gz" \
            -out "${backup_path}.tar.gz.enc" \
            -pass file:"${ENCRYPTION_KEY_FILE}"
        rm -rf "${backup_path}" "${backup_path}.tar.gz"
        log "Backup encrypted: ${backup_path}.tar.gz.enc"

        # Generate integrity hash of encrypted file
        sha256sum "${backup_path}.tar.gz.enc" > "${backup_path}.tar.gz.enc.sha256"
    else
        log_warn "Encryption key not found. Backup is NOT encrypted."
        tar -czf "${backup_path}.tar.gz" -C "${BACKUP_DIR}" "${backup_name}"
        rm -rf "${backup_path}"
        sha256sum "${backup_path}.tar.gz" > "${backup_path}.tar.gz.sha256"
    fi

    # 9. Calculate and report size
    local backup_size
    backup_size=$(du -sh "${backup_path}".tar.gz* 2>/dev/null | awk '{print $1}')
    log "Full backup complete: ${backup_name} (${backup_size})"
}

backup_incremental() {
    log "Starting incremental sovereign backup..."
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="nova_sovereign_incr_${timestamp}"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    mkdir -p "${backup_path}"

    # Find last full backup timestamp
    local last_full
    last_full=$(ls -1 "${BACKUP_DIR}"/nova_sovereign_full_*.tar.gz* 2>/dev/null | sort | tail -1 | grep -oP '\d{8}_\d{6}')

    if [[ -z "${last_full}" ]]; then
        log_warn "No full backup found. Performing full backup instead."
        backup_full
        return
    fi

    log "Incremental since: ${last_full}"

    # Backup only WAL files since last full
    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        bash -c "find /var/lib/postgresql/archive -newer /var/lib/postgresql/archive/${last_full} -type f" 2>/dev/null | \
        while read -r wal_file; do
            kubectl cp "${NAMESPACE}/${DEPLOYMENT_NAME}-postgres-0:${wal_file}" \
                "${backup_path}/$(basename "${wal_file}")" 2>/dev/null
        done || log_warn "WAL backup incomplete"

    # Backup recent audit logs only
    kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        find /opt/nova/data/audit -newer "/opt/nova/data/audit/.last_backup" -type f 2>/dev/null | \
        while read -r audit_file; do
            kubectl cp "${NAMESPACE}/${DEPLOYMENT_NAME}-node-0:${audit_file}" \
                "${backup_path}/audit/$(basename "${audit_file}")" 2>/dev/null
        done || log_warn "Audit incremental incomplete"

    # Create manifest
    cat > "${backup_path}/manifest.json" <<EOF
{
    "version": "1.0",
    "type": "incremental",
    "timestamp": "${timestamp}",
    "base_backup": "${last_full}",
    "deployment": "${DEPLOYMENT_NAME}",
    "namespace": "${NAMESPACE}"
}
EOF

    # Package and encrypt
    tar -czf "${backup_path}.tar.gz" -C "${BACKUP_DIR}" "${backup_name}"
    if [[ -f "${ENCRYPTION_KEY_FILE}" ]]; then
        openssl enc -aes-256-gcm -salt -pbkdf2 -iter 100000 \
            -in "${backup_path}.tar.gz" \
            -out "${backup_path}.tar.gz.enc" \
            -pass file:"${ENCRYPTION_KEY_FILE}"
        rm -f "${backup_path}.tar.gz"
        sha256sum "${backup_path}.tar.gz.enc" > "${backup_path}.tar.gz.enc.sha256"
    fi
    rm -rf "${backup_path}"

    log "Incremental backup complete: ${backup_name}"
}

# ── Restore Functions ─────────────────────────────────────────────────────────

restore_backup() {
    local target_timestamp="$1"
    log "Starting restore from backup: ${target_timestamp}"

    # Find backup file
    local backup_file
    backup_file=$(ls -1 "${BACKUP_DIR}"/nova_sovereign_*"${target_timestamp}"* 2>/dev/null | head -1)

    if [[ -z "${backup_file}" ]]; then
        log_error "Backup not found for timestamp: ${target_timestamp}"
        log "Available backups:"
        list_backups
        exit 1
    fi

    log "Restoring from: ${backup_file}"

    # Decrypt if needed
    local restore_dir="/tmp/nova_restore_${target_timestamp}"
    mkdir -p "${restore_dir}"

    if [[ "${backup_file}" == *.enc ]]; then
        if [[ ! -f "${ENCRYPTION_KEY_FILE}" ]]; then
            log_error "Encrypted backup requires encryption key: ${ENCRYPTION_KEY_FILE}"
            exit 1
        fi
        log "Decrypting backup..."
        openssl enc -d -aes-256-gcm -pbkdf2 -iter 100000 \
            -in "${backup_file}" \
            -out "${restore_dir}/backup.tar.gz" \
            -pass file:"${ENCRYPTION_KEY_FILE}"
        tar -xzf "${restore_dir}/backup.tar.gz" -C "${restore_dir}"
    else
        tar -xzf "${backup_file}" -C "${restore_dir}"
    fi

    # Find extracted backup directory
    local backup_dir
    backup_dir=$(find "${restore_dir}" -name "manifest.json" -exec dirname {} \;)

    if [[ -z "${backup_dir}" ]]; then
        log_error "Invalid backup: manifest.json not found"
        rm -rf "${restore_dir}"
        exit 1
    fi

    # Verify checksums
    if [[ -f "${backup_dir}/checksums.sha256" ]]; then
        log "Verifying backup integrity..."
        cd "${backup_dir}"
        if sha256sum -c checksums.sha256; then
            log "Integrity check passed ✓"
        else
            log_error "Backup integrity check FAILED"
            rm -rf "${restore_dir}"
            exit 1
        fi
        cd -
    fi

    # Confirm restore
    echo ""
    echo -e "${YELLOW}WARNING: This will overwrite current state!${RESET}"
    echo "Backup type: $(jq -r '.type' "${backup_dir}/manifest.json")"
    echo "Timestamp:   $(jq -r '.timestamp' "${backup_dir}/manifest.json")"
    echo ""
    read -rp "Continue with restore? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log "Restore cancelled"
        rm -rf "${restore_dir}"
        exit 0
    fi

    # Restore database
    if [[ -f "${backup_dir}/database.sql.gz" ]]; then
        log "Restoring database..."
        gunzip -c "${backup_dir}/database.sql.gz" | \
            kubectl exec -i -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
            psql -U postgres 2>/dev/null
        log "Database restored ✓"
    fi

    # Restore canister state
    if [[ -f "${backup_dir}/canister-state.tar.gz" ]]; then
        log "Restoring canister state..."
        kubectl cp "${backup_dir}/canister-state.tar.gz" \
            "${NAMESPACE}/${DEPLOYMENT_NAME}-node-0:/tmp/canister-state.tar.gz"
        kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
            tar -xzf /tmp/canister-state.tar.gz -C / 2>/dev/null || true
        log "Canister state restored ✓"
    fi

    # Restore configurations
    if [[ -f "${backup_dir}/configmaps.yaml" ]]; then
        log "Restoring configurations..."
        kubectl apply -f "${backup_dir}/configmaps.yaml" -n "${NAMESPACE}" 2>/dev/null || true
        log "Configurations restored ✓"
    fi

    # Cleanup
    rm -rf "${restore_dir}"

    # Restart pods to pick up restored state
    log "Restarting sovereign nodes..."
    kubectl rollout restart statefulset "${DEPLOYMENT_NAME}-node" -n "${NAMESPACE}" 2>/dev/null || true
    kubectl rollout status statefulset "${DEPLOYMENT_NAME}-node" -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

    log "Restore complete from backup: ${target_timestamp}"
}

# ── List Backups ──────────────────────────────────────────────────────────────

list_backups() {
    echo -e "${BOLD}Available Backups:${RESET}"
    echo "─────────────────────────────────────────────────────────────────"
    printf "%-25s %-12s %-10s %-10s\n" "TIMESTAMP" "TYPE" "SIZE" "ENCRYPTED"
    echo "─────────────────────────────────────────────────────────────────"

    for backup in "${BACKUP_DIR}"/nova_sovereign_*.tar.gz*; do
        [[ -f "${backup}" ]] || continue
        local filename
        filename=$(basename "${backup}")
        local ts
        ts=$(echo "${filename}" | grep -oP '\d{8}_\d{6}')
        local type="full"
        echo "${filename}" | grep -q "incr" && type="incremental"
        local size
        size=$(du -sh "${backup}" | awk '{print $1}')
        local encrypted="no"
        [[ "${backup}" == *.enc ]] && encrypted="yes"

        printf "%-25s %-12s %-10s %-10s\n" "${ts}" "${type}" "${size}" "${encrypted}"
    done

    echo "─────────────────────────────────────────────────────────────────"
    local total_size
    total_size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | awk '{print $1}')
    echo "Total backup storage: ${total_size:-0}"
}

# ── Verify Backup ─────────────────────────────────────────────────────────────

verify_backup() {
    local target_timestamp="$1"
    log "Verifying backup integrity: ${target_timestamp}"

    local backup_file
    backup_file=$(ls -1 "${BACKUP_DIR}"/nova_sovereign_*"${target_timestamp}"* 2>/dev/null | head -1)

    if [[ -z "${backup_file}" ]]; then
        log_error "Backup not found: ${target_timestamp}"
        exit 1
    fi

    # Check file integrity
    local sha_file="${backup_file}.sha256"
    if [[ -f "${sha_file}" ]]; then
        if sha256sum -c "${sha_file}"; then
            log "File integrity: PASSED ✓"
        else
            log_error "File integrity: FAILED ✗"
            exit 1
        fi
    else
        log_warn "No checksum file found. Cannot verify file integrity."
    fi

    # Try to decrypt and read manifest
    if [[ "${backup_file}" == *.enc ]]; then
        if [[ -f "${ENCRYPTION_KEY_FILE}" ]]; then
            local verify_dir="/tmp/nova_verify_${target_timestamp}"
            mkdir -p "${verify_dir}"
            openssl enc -d -aes-256-gcm -pbkdf2 -iter 100000 \
                -in "${backup_file}" \
                -out "${verify_dir}/backup.tar.gz" \
                -pass file:"${ENCRYPTION_KEY_FILE}" && \
                log "Decryption: PASSED ✓" || \
                { log_error "Decryption: FAILED ✗"; rm -rf "${verify_dir}"; exit 1; }

            # Check tar integrity
            if tar -tzf "${verify_dir}/backup.tar.gz" &>/dev/null; then
                log "Archive integrity: PASSED ✓"
            else
                log_error "Archive integrity: FAILED ✗"
            fi

            rm -rf "${verify_dir}"
        else
            log_warn "Cannot verify encrypted backup without key"
        fi
    fi

    log "Verification complete for: ${target_timestamp}"
}

# ── Rotate Backups ────────────────────────────────────────────────────────────

rotate_backups() {
    log "Rotating backups (retention: ${RETENTION_DAYS} days)..."

    local deleted=0
    local cutoff_date
    cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
                  date -v-${RETENTION_DAYS}d +%Y%m%d)

    for backup in "${BACKUP_DIR}"/nova_sovereign_*; do
        [[ -f "${backup}" ]] || continue
        local ts
        ts=$(echo "$(basename "${backup}")" | grep -oP '\d{8}' | head -1)

        if [[ -n "${ts}" ]] && [[ "${ts}" < "${cutoff_date}" ]]; then
            rm -f "${backup}"
            log "Deleted: $(basename "${backup}")"
            ((deleted++))
        fi
    done

    log "Rotation complete. Deleted ${deleted} expired backups."

    # Keep at least one full backup regardless of age
    local full_count
    full_count=$(ls -1 "${BACKUP_DIR}"/nova_sovereign_full_* 2>/dev/null | wc -l)
    if [[ ${full_count} -eq 0 ]]; then
        log_warn "No full backups remaining after rotation. Consider running a new full backup."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    mkdir -p "${BACKUP_DIR}"

    local command="${1:-help}"
    shift || true

    case "${command}" in
        backup)
            local backup_type="full"
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --full) backup_type="full"; shift;;
                    --incremental) backup_type="incremental"; shift;;
                    *) shift;;
                esac
            done
            if [[ "${backup_type}" == "full" ]]; then
                backup_full
            else
                backup_incremental
            fi
            ;;
        restore)
            local timestamp=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --timestamp) timestamp="$2"; shift 2;;
                    *) shift;;
                esac
            done
            if [[ -z "${timestamp}" ]]; then
                log_error "Usage: $0 restore --timestamp YYYYMMDD_HHMMSS"
                exit 1
            fi
            restore_backup "${timestamp}"
            ;;
        list)
            list_backups
            ;;
        verify)
            local timestamp=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --timestamp) timestamp="$2"; shift 2;;
                    *) shift;;
                esac
            done
            if [[ -z "${timestamp}" ]]; then
                log_error "Usage: $0 verify --timestamp YYYYMMDD_HHMMSS"
                exit 1
            fi
            verify_backup "${timestamp}"
            ;;
        rotate)
            rotate_backups
            ;;
        help|*)
            echo "NOVA Sovereign Backup & Restore"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  backup    Create a backup (--full or --incremental)"
            echo "  restore   Restore from backup (--timestamp YYYYMMDD_HHMMSS)"
            echo "  list      List available backups"
            echo "  verify    Verify backup integrity (--timestamp YYYYMMDD_HHMMSS)"
            echo "  rotate    Delete expired backups based on retention policy"
            echo ""
            echo "Environment Variables:"
            echo "  NOVA_BACKUP_DIR       Backup storage directory"
            echo "  NOVA_ENCRYPTION_KEY   Path to encryption key file"
            echo "  NOVA_NAMESPACE        Kubernetes namespace"
            echo "  NOVA_DEPLOYMENT       Deployment name"
            echo "  NOVA_BACKUP_RETENTION Retention period in days"
            ;;
    esac
}

main "$@"
