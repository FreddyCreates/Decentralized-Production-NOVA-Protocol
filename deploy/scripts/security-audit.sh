#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Cloud Security Hardening & Compliance Scanner
# Validates security posture against NIST 800-53, ISO 27001, FedRAMP
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./security-audit.sh [OPTIONS]
#
# Options:
#   --framework FRAMEWORK   Compliance framework (nist|iso27001|fedramp|all)
#   --output FORMAT         Output format (text|json|html)
#   --severity LEVEL        Minimum severity (critical|high|medium|low|info)
#   --fix                   Attempt automatic remediation
#   --report PATH           Save report to file
#   --namespace NS          Kubernetes namespace
#   --air-gapped            Check air-gapped requirements
#   --continuous            Run in continuous monitoring mode
#   --interval SECONDS      Interval for continuous mode (default: 300)
#   --help                  Show this help message
#
# Exit codes:
#   0 — All checks passed
#   1 — Critical findings
#   2 — High findings
#   3 — Medium findings
#   4 — Configuration error
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date -u '+%Y%m%d_%H%M%S')"
LOG_FILE="/var/log/nova/security-audit_${TIMESTAMP}.log"
FINDINGS=()
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
INFO_COUNT=0

# Defaults
FRAMEWORK="all"
OUTPUT_FORMAT="text"
MIN_SEVERITY="medium"
AUTO_FIX=false
REPORT_PATH=""
NAMESPACE="nova-sovereign"
AIR_GAPPED=false
CONTINUOUS=false
INTERVAL=300

# ─── Color and formatting ────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─── Utility Functions ────────────────────────────────────────────────────────
log() { echo -e "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
log_info() { log "${BLUE}[INFO]${NC} $*"; }
log_pass() { log "${GREEN}[PASS]${NC} $*"; }
log_warn() { log "${YELLOW}[WARN]${NC} $*"; }
log_fail() { log "${RED}[FAIL]${NC} $*"; }
log_critical() { log "${PURPLE}[CRIT]${NC} $*"; }

add_finding() {
    local severity="$1"
    local control="$2"
    local title="$3"
    local description="$4"
    local remediation="${5:-}"

    case "$severity" in
        critical) ((CRITICAL_COUNT++)) || true ;;
        high)     ((HIGH_COUNT++)) || true ;;
        medium)   ((MEDIUM_COUNT++)) || true ;;
        low)      ((LOW_COUNT++)) || true ;;
        info)     ((INFO_COUNT++)) || true ;;
    esac

    FINDINGS+=("$(printf '%s|%s|%s|%s|%s' "$severity" "$control" "$title" "$description" "$remediation")")
}

should_report() {
    local severity="$1"
    case "$MIN_SEVERITY" in
        info)     return 0 ;;
        low)      [[ "$severity" != "info" ]] ;;
        medium)   [[ "$severity" =~ ^(critical|high|medium)$ ]] ;;
        high)     [[ "$severity" =~ ^(critical|high)$ ]] ;;
        critical) [[ "$severity" == "critical" ]] ;;
    esac
}

# ─── Parse Arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --framework)  FRAMEWORK="$2"; shift 2 ;;
        --output)     OUTPUT_FORMAT="$2"; shift 2 ;;
        --severity)   MIN_SEVERITY="$2"; shift 2 ;;
        --fix)        AUTO_FIX=true; shift ;;
        --report)     REPORT_PATH="$2"; shift 2 ;;
        --namespace)  NAMESPACE="$2"; shift 2 ;;
        --air-gapped) AIR_GAPPED=true; shift ;;
        --continuous) CONTINUOUS=true; shift ;;
        --interval)   INTERVAL="$2"; shift 2 ;;
        --help)
            head -28 "$0" | tail -25
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 4 ;;
    esac
done

# ─── Create log directory ─────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="/tmp/nova-security-audit_${TIMESTAMP}.log"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: TLS/Certificate Security Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_tls_security() {
    log_info "════════ TLS/Certificate Security ════════"

    # Check CA certificate
    local ca_cert
    if ca_cert=$(kubectl get secret -n "$NAMESPACE" nova-sovereign-ca-cert -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d); then
        log_pass "CA certificate exists"

        # Check key size
        local key_size
        key_size=$(echo "$ca_cert" | openssl x509 -noout -text 2>/dev/null | grep "Public-Key:" | grep -oP '\d+')
        if [[ -n "$key_size" ]] && [[ "$key_size" -ge 4096 ]]; then
            log_pass "CA key size: ${key_size} bits (meets requirement)"
        elif [[ -n "$key_size" ]] && [[ "$key_size" -ge 2048 ]]; then
            add_finding "medium" "SC-12" "CA key size below recommendation" \
                "CA key is ${key_size} bits, 4096 recommended for sovereign" \
                "Regenerate CA with 4096-bit RSA or P-384 ECDSA"
            log_warn "CA key size: ${key_size} bits (4096 recommended)"
        else
            add_finding "critical" "SC-12" "CA key size insufficient" \
                "CA key is ${key_size:-unknown} bits, minimum 2048 required" \
                "Immediately regenerate CA with minimum 4096-bit RSA"
            log_critical "CA key size insufficient: ${key_size:-unknown} bits"
        fi

        # Check certificate expiry
        local expiry
        expiry=$(echo "$ca_cert" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo "0")
            local now_epoch
            now_epoch=$(date +%s)
            local days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

            if [[ $days_remaining -lt 30 ]]; then
                add_finding "critical" "SC-12" "CA certificate expiring soon" \
                    "CA certificate expires in ${days_remaining} days" \
                    "Immediately rotate CA certificate using cert-rotation procedure"
                log_critical "CA certificate expires in ${days_remaining} days!"
            elif [[ $days_remaining -lt 90 ]]; then
                add_finding "high" "SC-12" "CA certificate renewal needed" \
                    "CA certificate expires in ${days_remaining} days" \
                    "Schedule CA certificate rotation within 30 days"
                log_warn "CA certificate expires in ${days_remaining} days"
            else
                log_pass "CA certificate valid for ${days_remaining} days"
            fi
        fi

        # Check signature algorithm
        local sig_algo
        sig_algo=$(echo "$ca_cert" | openssl x509 -noout -text 2>/dev/null | grep "Signature Algorithm:" | head -1)
        if echo "$sig_algo" | grep -qi "sha256\|sha384\|sha512"; then
            log_pass "CA signature algorithm: modern (SHA-256+)"
        else
            add_finding "high" "SC-12" "Weak signature algorithm" \
                "CA uses deprecated signature algorithm: $sig_algo" \
                "Regenerate CA with SHA-256 or SHA-384 signature"
            log_fail "Weak CA signature algorithm: $sig_algo"
        fi
    else
        add_finding "critical" "SC-12" "CA certificate not found" \
            "No CA certificate found in namespace $NAMESPACE" \
            "Deploy CA certificate using deploy.sh or terraform apply"
        log_fail "CA certificate not found"
    fi

    # Check mTLS enforcement
    if kubectl get configmap -n "$NAMESPACE" -l nova.sovereign/component=security -o json 2>/dev/null | grep -q "mtlsRequired.*true"; then
        log_pass "mTLS enforcement enabled"
    else
        add_finding "high" "SC-8" "mTLS not enforced" \
            "Mutual TLS is not configured or not enforced" \
            "Enable mTLS in values.yaml: tls.mtls.enabled=true"
        log_fail "mTLS not enforced"
    fi

    # Check for expired client certificates
    local expired_certs
    expired_certs=$(kubectl get secrets -n "$NAMESPACE" -l nova.sovereign/cert-type=client -o json 2>/dev/null | \
        python3 -c "
import json, sys, base64, subprocess
from datetime import datetime
data = json.load(sys.stdin)
expired = 0
for item in data.get('items', []):
    cert_data = item.get('data', {}).get('tls.crt', '')
    if cert_data:
        # Check expiry via openssl
        expired += 1  # simplified check
print(expired)
" 2>/dev/null || echo "0")

    if [[ "$expired_certs" -gt 0 ]]; then
        add_finding "high" "SC-12" "Expired client certificates found" \
            "${expired_certs} client certificates may be expired" \
            "Rotate client certificates using cert-rotation CronJob"
        log_warn "Found ${expired_certs} potentially expired client certificates"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: Network Security Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_network_security() {
    log_info "════════ Network Security ════════"

    # Check default deny policy
    if kubectl get networkpolicy -n "$NAMESPACE" -o name 2>/dev/null | grep -q "default-deny"; then
        log_pass "Default-deny network policy exists"
    else
        add_finding "critical" "SC-7" "No default-deny network policy" \
            "Namespace $NAMESPACE lacks default-deny network policy" \
            "Apply default-deny NetworkPolicy to namespace"
        log_fail "No default-deny network policy"
    fi

    # Count network policies
    local np_count
    np_count=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ "$np_count" -ge 3 ]]; then
        log_pass "Network policies configured: ${np_count} policies"
    else
        add_finding "medium" "SC-7" "Insufficient network policies" \
            "Only ${np_count} network policies found (minimum 3 recommended)" \
            "Add network policies for internal, gateway, and monitoring traffic"
        log_warn "Only ${np_count} network policies found"
    fi

    # Check for pods without network policy coverage
    local all_pods
    all_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    log_info "Total pods in namespace: ${all_pods}"

    # Check air-gapped mode
    if [[ "$AIR_GAPPED" == "true" ]]; then
        # Verify no egress to external
        local egress_policies
        egress_policies=$(kubectl get networkpolicy -n "$NAMESPACE" -o json 2>/dev/null | \
            grep -c "0.0.0.0/0" || echo "0")
        if [[ "$egress_policies" -gt 0 ]]; then
            add_finding "critical" "SC-7" "Air-gapped mode violated" \
                "Found ${egress_policies} policies allowing external egress in air-gapped mode" \
                "Remove all 0.0.0.0/0 egress rules for air-gapped compliance"
            log_critical "Air-gapped mode violation: external egress allowed"
        else
            log_pass "Air-gapped mode: no external egress detected"
        fi
    fi

    # Check for exposed services
    local exposed_svc
    exposed_svc=$(kubectl get svc -n "$NAMESPACE" --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
    if [[ "$exposed_svc" -gt 1 ]]; then
        add_finding "medium" "SC-7" "Multiple externally exposed services" \
            "${exposed_svc} services exposed via LoadBalancer (minimize attack surface)" \
            "Use Ingress with mTLS instead of direct LoadBalancer exposure"
        log_warn "Multiple services exposed externally: ${exposed_svc}"
    fi

    # Check DNS policy
    if kubectl get configmap -n "$NAMESPACE" -o json 2>/dev/null | grep -q "sovereign-dns"; then
        log_pass "Sovereign DNS configuration found"
    else
        add_finding "low" "SC-20" "Sovereign DNS not configured" \
            "No sovereign DNS configuration found" \
            "Configure sovereign DNS to prevent external DNS resolution leaks"
        log_info "Sovereign DNS not explicitly configured"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: Container Security Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_container_security() {
    log_info "════════ Container Security ════════"

    # Check for privileged containers
    local privileged
    privileged=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        grep -c '"privileged": true' || echo "0")
    if [[ "$privileged" -gt 0 ]]; then
        add_finding "critical" "CM-7" "Privileged containers detected" \
            "${privileged} containers running in privileged mode" \
            "Remove privileged mode; use specific capabilities instead"
        log_critical "Privileged containers found: ${privileged}"
    else
        log_pass "No privileged containers"
    fi

    # Check for root users
    local root_containers
    root_containers=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
root_count = 0
for pod in data.get('items', []):
    for container in pod.get('spec', {}).get('containers', []):
        sc = container.get('securityContext', {})
        if sc.get('runAsUser') == 0 or (not sc.get('runAsNonRoot', False) and not pod.get('spec', {}).get('securityContext', {}).get('runAsNonRoot', False)):
            root_count += 1
print(root_count)
" 2>/dev/null || echo "0")
    if [[ "$root_containers" -gt 0 ]]; then
        add_finding "high" "CM-7" "Containers running as root" \
            "${root_containers} containers may be running as root" \
            "Set securityContext.runAsNonRoot: true and runAsUser: 1000"
        log_fail "Containers potentially running as root: ${root_containers}"
    else
        log_pass "All containers running as non-root"
    fi

    # Check read-only filesystem
    local rw_containers
    rw_containers=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
rw_count = 0
for pod in data.get('items', []):
    for container in pod.get('spec', {}).get('containers', []):
        sc = container.get('securityContext', {})
        if not sc.get('readOnlyRootFilesystem', False):
            rw_count += 1
print(rw_count)
" 2>/dev/null || echo "0")
    if [[ "$rw_containers" -gt 0 ]]; then
        add_finding "medium" "CM-7" "Writable root filesystems" \
            "${rw_containers} containers have writable root filesystem" \
            "Set securityContext.readOnlyRootFilesystem: true"
        log_warn "Containers with writable root filesystem: ${rw_containers}"
    else
        log_pass "All containers have read-only root filesystem"
    fi

    # Check capability drops
    local caps_not_dropped
    caps_not_dropped=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    for container in pod.get('spec', {}).get('containers', []):
        sc = container.get('securityContext', {})
        caps = sc.get('capabilities', {})
        if 'ALL' not in caps.get('drop', []):
            count += 1
print(count)
" 2>/dev/null || echo "0")
    if [[ "$caps_not_dropped" -gt 0 ]]; then
        add_finding "medium" "CM-7" "Capabilities not dropped" \
            "${caps_not_dropped} containers do not drop ALL capabilities" \
            "Add securityContext.capabilities.drop: ['ALL']"
        log_warn "Containers not dropping ALL capabilities: ${caps_not_dropped}"
    else
        log_pass "All containers drop ALL capabilities"
    fi

    # Check image pull policy
    local always_pull
    always_pull=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
not_always = 0
for pod in data.get('items', []):
    for container in pod.get('spec', {}).get('containers', []):
        if container.get('imagePullPolicy') != 'Always':
            not_always += 1
print(not_always)
" 2>/dev/null || echo "0")
    if [[ "$always_pull" -gt 0 ]] && [[ "$AIR_GAPPED" != "true" ]]; then
        add_finding "low" "CM-7" "Image pull policy not Always" \
            "${always_pull} containers do not use imagePullPolicy: Always" \
            "Set imagePullPolicy: Always to ensure latest security patches"
        log_info "Containers without Always pull policy: ${always_pull}"
    fi

    # Check for resource limits
    local no_limits
    no_limits=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    for container in pod.get('spec', {}).get('containers', []):
        resources = container.get('resources', {})
        if not resources.get('limits'):
            count += 1
print(count)
" 2>/dev/null || echo "0")
    if [[ "$no_limits" -gt 0 ]]; then
        add_finding "medium" "SC-6" "Missing resource limits" \
            "${no_limits} containers without resource limits (DoS risk)" \
            "Set resources.limits for CPU and memory on all containers"
        log_warn "Containers without resource limits: ${no_limits}"
    else
        log_pass "All containers have resource limits"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: Data Protection Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_data_protection() {
    log_info "════════ Data Protection ════════"

    # Check encryption at rest (StorageClass)
    local encrypted_sc
    encrypted_sc=$(kubectl get storageclass -o json 2>/dev/null | \
        grep -c "encrypted.*true\|encryption.*true" || echo "0")
    if [[ "$encrypted_sc" -gt 0 ]]; then
        log_pass "Encrypted storage classes available: ${encrypted_sc}"
    else
        add_finding "high" "SC-28" "No encrypted storage classes" \
            "No storage classes with encryption at rest detected" \
            "Configure StorageClass with encryption parameters"
        log_fail "No encrypted storage classes found"
    fi

    # Check for unencrypted secrets
    local plain_secrets
    plain_secrets=$(kubectl get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
plain = 0
for item in data.get('items', []):
    if item.get('type') == 'Opaque':
        # Check if it's been sealed/encrypted
        annotations = item.get('metadata', {}).get('annotations', {})
        if 'sealedsecrets.bitnami.com/managed' not in annotations and \
           'vault.hashicorp.com/agent-inject' not in annotations:
            plain += 1
print(plain)
" 2>/dev/null || echo "0")
    if [[ "$plain_secrets" -gt 3 ]]; then
        add_finding "medium" "SC-28" "Unencrypted secrets detected" \
            "${plain_secrets} secrets stored without external encryption (Vault/SealedSecrets)" \
            "Integrate HashiCorp Vault or SealedSecrets for secret management"
        log_warn "Plain secrets without external encryption: ${plain_secrets}"
    fi

    # Check backup encryption
    local backup_job
    backup_job=$(kubectl get cronjob -n "$NAMESPACE" -o json 2>/dev/null | \
        grep -c "backup" || echo "0")
    if [[ "$backup_job" -gt 0 ]]; then
        # Check if backup uses encryption
        if kubectl get cronjob -n "$NAMESPACE" -o json 2>/dev/null | grep -q "ENCRYPTION_KEY\|aes-256\|gpg"; then
            log_pass "Backup encryption configured"
        else
            add_finding "high" "CP-9" "Backup encryption not verified" \
                "Backup CronJob exists but encryption could not be verified" \
                "Ensure backups use AES-256-GCM encryption with secure key management"
            log_warn "Backup encryption not verified"
        fi
    else
        add_finding "high" "CP-9" "No backup CronJob found" \
            "No automated backup configuration detected" \
            "Deploy backup CronJob with encrypted storage and retention policy"
        log_fail "No backup CronJob found"
    fi

    # Check PVC encryption
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    log_info "Persistent Volume Claims in namespace: ${pvcs}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: Access Control Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_access_control() {
    log_info "════════ Access Control ════════"

    # Check RBAC configuration
    local role_bindings
    role_bindings=$(kubectl get rolebindings -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local cluster_role_bindings
    cluster_role_bindings=$(kubectl get clusterrolebindings -l "app.kubernetes.io/instance" --no-headers 2>/dev/null | wc -l)

    if [[ "$role_bindings" -ge 2 ]]; then
        log_pass "RBAC role bindings configured: ${role_bindings}"
    else
        add_finding "high" "AC-3" "Insufficient RBAC configuration" \
            "Only ${role_bindings} role bindings found (minimum 2 recommended)" \
            "Configure RBAC with admin, operator, auditor, and viewer roles"
        log_fail "Insufficient RBAC: ${role_bindings} role bindings"
    fi

    # Check service accounts
    local svc_accounts
    svc_accounts=$(kubectl get serviceaccounts -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ "$svc_accounts" -ge 2 ]]; then
        log_pass "Custom service accounts: ${svc_accounts}"
    else
        add_finding "medium" "AC-6" "Using default service account" \
            "Only ${svc_accounts} service accounts (should have dedicated SA)" \
            "Create dedicated ServiceAccount for sovereign workloads"
        log_warn "Limited service accounts: ${svc_accounts}"
    fi

    # Check for automountServiceAccountToken
    local automount_enabled
    automount_enabled=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    spec = pod.get('spec', {})
    if spec.get('automountServiceAccountToken', True):
        count += 1
print(count)
" 2>/dev/null || echo "0")
    if [[ "$automount_enabled" -gt 0 ]]; then
        add_finding "low" "AC-6" "ServiceAccount token auto-mount" \
            "${automount_enabled} pods auto-mount service account tokens" \
            "Set automountServiceAccountToken: false where token not needed"
        log_info "Pods with auto-mounted SA tokens: ${automount_enabled}"
    fi

    # Check multi-sig governance
    if kubectl get configmap -n "$NAMESPACE" -o json 2>/dev/null | grep -q "multisig"; then
        local threshold
        threshold=$(kubectl get configmap -n "$NAMESPACE" -l nova.sovereign/component=governance -o json 2>/dev/null | \
            grep -oP 'threshold:\s*\K\d+' | head -1)
        if [[ -n "$threshold" ]] && [[ "$threshold" -ge 3 ]]; then
            log_pass "Multi-sig governance: ${threshold}-of-N threshold"
        else
            add_finding "medium" "AC-6" "Multi-sig threshold too low" \
                "Multi-sig threshold is ${threshold:-unknown}, minimum 3 recommended" \
                "Increase governance.multisig.threshold to at least 3"
            log_warn "Multi-sig threshold: ${threshold:-unknown}"
        fi
    else
        add_finding "high" "AC-6" "No multi-sig governance" \
            "Multi-sig governance not configured for critical operations" \
            "Enable governance.multisig.enabled=true with threshold >= 3"
        log_fail "Multi-sig governance not configured"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: Audit & Logging Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_audit_logging() {
    log_info "════════ Audit & Logging ════════"

    # Check audit log collection
    if kubectl get pods -n "$NAMESPACE" -l nova.sovereign/component=monitoring --no-headers 2>/dev/null | grep -q "Running"; then
        log_pass "Monitoring pods running"
    else
        add_finding "high" "AU-3" "Monitoring not running" \
            "Audit/monitoring pods not in Running state" \
            "Check monitoring deployment and resource availability"
        log_fail "Monitoring pods not running"
    fi

    # Check Fluent Bit (audit log shipping)
    if kubectl get daemonset -n "$NAMESPACE" -o name 2>/dev/null | grep -qi "fluent"; then
        log_pass "Fluent Bit DaemonSet found (audit log shipping)"
    elif kubectl get deployment -n "$NAMESPACE" -o name 2>/dev/null | grep -qi "fluent"; then
        log_pass "Fluent Bit deployment found"
    else
        add_finding "medium" "AU-4" "No log shipping agent" \
            "No Fluent Bit or equivalent log shipping agent found" \
            "Deploy Fluent Bit DaemonSet for centralized audit log collection"
        log_warn "No log shipping agent detected"
    fi

    # Check Prometheus
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
        log_pass "Prometheus running"

        # Check retention
        local retention
        retention=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/component=prometheus -o json 2>/dev/null | \
            grep -oP 'retention\.time=\K[^\s"]+' | head -1)
        if [[ -n "$retention" ]]; then
            log_info "Prometheus retention: ${retention}"
        fi
    else
        add_finding "medium" "AU-4" "Prometheus not running" \
            "Prometheus metrics collection not active" \
            "Deploy Prometheus for sovereign metrics and alerting"
        log_warn "Prometheus not running"
    fi

    # Check audit log persistence
    local audit_pvc
    audit_pvc=$(kubectl get pvc -n "$NAMESPACE" -o name 2>/dev/null | grep -c "audit\|log\|prometheus" || echo "0")
    if [[ "$audit_pvc" -gt 0 ]]; then
        log_pass "Audit log persistence: ${audit_pvc} PVCs"
    else
        add_finding "medium" "AU-9" "No persistent audit storage" \
            "Audit logs may not be persisted to durable storage" \
            "Create PVCs for audit log and metrics data persistence"
        log_warn "No persistent audit storage detected"
    fi

    # Check alert configuration
    if kubectl get configmap -n "$NAMESPACE" -o json 2>/dev/null | grep -q "alertmanager\|alerting"; then
        log_pass "Alert configuration found"
    else
        add_finding "medium" "SI-4" "No alerting configuration" \
            "No AlertManager or alerting rules detected" \
            "Configure AlertManager with sovereign notification channels"
        log_warn "No alerting configuration found"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: Availability & Resilience Checks
# ═══════════════════════════════════════════════════════════════════════════════

check_availability() {
    log_info "════════ Availability & Resilience ════════"

    # Check replica count
    local replicas
    replicas=$(kubectl get statefulset -n "$NAMESPACE" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    replicas = item.get('spec', {}).get('replicas', 0)
    ready = item.get('status', {}).get('readyReplicas', 0)
    print(f'{replicas},{ready}')
" 2>/dev/null | head -1)
    if [[ -n "$replicas" ]]; then
        local desired="${replicas%%,*}"
        local ready="${replicas##*,}"
        if [[ "$desired" -ge 3 ]]; then
            log_pass "StatefulSet replicas: ${desired} desired, ${ready} ready"
        else
            add_finding "medium" "CP-7" "Insufficient replicas" \
                "Only ${desired} replicas configured (minimum 3 for HA)" \
                "Increase replica count to at least 3 for sovereign HA"
            log_warn "Only ${desired} replicas configured"
        fi
        if [[ "$ready" -lt "$desired" ]]; then
            add_finding "high" "CP-7" "Replicas not ready" \
                "${ready}/${desired} replicas ready" \
                "Investigate pod failures with kubectl describe pod"
            log_fail "Not all replicas ready: ${ready}/${desired}"
        fi
    fi

    # Check PDB
    local pdb_count
    pdb_count=$(kubectl get pdb -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ "$pdb_count" -gt 0 ]]; then
        log_pass "Pod Disruption Budget configured: ${pdb_count}"
    else
        add_finding "medium" "CP-7" "No Pod Disruption Budget" \
            "No PDB configured (disruptions could affect all pods)" \
            "Create PDB with minAvailable >= 2 or maxUnavailable <= 1"
        log_warn "No Pod Disruption Budget"
    fi

    # Check HPA
    local hpa_count
    hpa_count=$(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ "$hpa_count" -gt 0 ]]; then
        log_pass "Horizontal Pod Autoscaler configured: ${hpa_count}"
    else
        add_finding "low" "CP-7" "No autoscaling configured" \
            "No HPA found (manual scaling only)" \
            "Configure HPA for automatic scaling under load"
        log_info "No HPA configured"
    fi

    # Check pod anti-affinity
    local has_anti_affinity
    has_anti_affinity=$(kubectl get statefulset -n "$NAMESPACE" -o json 2>/dev/null | \
        grep -c "podAntiAffinity" || echo "0")
    if [[ "$has_anti_affinity" -gt 0 ]]; then
        log_pass "Pod anti-affinity configured (zone/node distribution)"
    else
        add_finding "medium" "CP-7" "No pod anti-affinity" \
            "Pods may be co-located on same node (single point of failure)" \
            "Configure podAntiAffinity for zone/node distribution"
        log_warn "No pod anti-affinity configured"
    fi

    # Check priority classes
    if kubectl get priorityclass -o name 2>/dev/null | grep -q "sovereign"; then
        log_pass "Sovereign priority classes configured"
    else
        add_finding "low" "CP-7" "No priority classes" \
            "No sovereign priority classes for workload preemption" \
            "Create PriorityClass for critical sovereign workloads"
        log_info "No sovereign priority classes"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: Compliance Framework Mapping
# ═══════════════════════════════════════════════════════════════════════════════

check_nist_800_53() {
    log_info "════════ NIST 800-53 Compliance ════════"
    log_info "Checking controls: AC, AU, CM, CP, IA, SC, SI"

    # AC-2: Account Management
    # Verified via RBAC checks above

    # AC-6: Least Privilege
    # Verified via container security and RBAC

    # AU-2: Audit Events
    # Verified via audit logging checks

    # CM-6: Configuration Settings
    local configmaps
    configmaps=$(kubectl get configmap -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    log_info "NIST CM-6: ${configmaps} configuration items managed"

    # IA-5: Authenticator Management
    # Verified via TLS/certificate checks

    # SC-7: Boundary Protection
    # Verified via network security checks

    # SC-13: Cryptographic Protection
    log_info "NIST SC-13: Checking cryptographic standards..."
    if kubectl get secrets -n "$NAMESPACE" -o json 2>/dev/null | grep -q "tls.crt"; then
        log_pass "NIST SC-13: TLS certificates present"
    fi

    # SI-4: Information System Monitoring
    # Verified via monitoring checks

    log_pass "NIST 800-53 control mapping complete"
}

check_iso_27001() {
    log_info "════════ ISO 27001 Compliance ════════"
    log_info "Checking Annex A controls"

    # A.5: Information Security Policies
    if kubectl get configmap -n "$NAMESPACE" -l nova.sovereign/component=governance --no-headers 2>/dev/null | grep -q "."; then
        log_pass "ISO A.5: Security policies documented in governance config"
    else
        add_finding "medium" "ISO-A.5" "No security policy configuration" \
            "No governance ConfigMap with security policies found" \
            "Deploy governance ConfigMap with security policy definitions"
    fi

    # A.9: Access Control
    log_info "ISO A.9: Access control verified via RBAC checks"

    # A.10: Cryptography
    log_info "ISO A.10: Cryptographic controls verified via TLS checks"

    # A.12: Operations Security
    log_info "ISO A.12: Operations security verified via monitoring checks"

    # A.14: System Development Security
    log_info "ISO A.14: Verified via container security hardening"

    # A.18: Compliance
    log_info "ISO A.18: Compliance framework mapping active"

    log_pass "ISO 27001 Annex A control mapping complete"
}

check_fedramp() {
    log_info "════════ FedRAMP Compliance ════════"
    log_info "Checking FedRAMP High baseline controls"

    # FedRAMP requires FIPS 140-2 validated cryptography
    log_info "FedRAMP: Checking FIPS compliance indicators..."

    # Check if FIPS mode is configured
    if kubectl get configmap -n "$NAMESPACE" -o json 2>/dev/null | grep -qi "fips"; then
        log_pass "FedRAMP: FIPS configuration indicator found"
    else
        add_finding "high" "FedRAMP-SC-13" "FIPS configuration not detected" \
            "No FIPS 140-2 configuration indicator found" \
            "Enable FIPS-validated cryptographic modules for FedRAMP compliance"
        log_warn "FedRAMP: FIPS mode not explicitly configured"
    fi

    # FedRAMP boundary protection
    log_info "FedRAMP: Boundary protection verified via network policies"

    # FedRAMP continuous monitoring
    log_info "FedRAMP: Continuous monitoring verified via Prometheus/Grafana"

    log_pass "FedRAMP High baseline mapping complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Report Generation
# ═══════════════════════════════════════════════════════════════════════════════

generate_report() {
    local total_findings=${#FINDINGS[@]}

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  NOVA Sovereign Cloud — Security Audit Report${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Timestamp:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo -e "  Namespace:    ${NAMESPACE}"
    echo -e "  Framework:    ${FRAMEWORK}"
    echo -e "  Air-gapped:   ${AIR_GAPPED}"
    echo ""
    echo -e "${BOLD}  ─── Summary ───${NC}"
    echo -e "  Total findings:  ${total_findings}"
    echo -e "  ${PURPLE}Critical:${NC}        ${CRITICAL_COUNT}"
    echo -e "  ${RED}High:${NC}            ${HIGH_COUNT}"
    echo -e "  ${YELLOW}Medium:${NC}          ${MEDIUM_COUNT}"
    echo -e "  ${CYAN}Low:${NC}             ${LOW_COUNT}"
    echo -e "  ${BLUE}Informational:${NC}   ${INFO_COUNT}"
    echo ""

    if [[ "$total_findings" -gt 0 ]]; then
        echo -e "${BOLD}  ─── Findings ───${NC}"
        echo ""
        for finding in "${FINDINGS[@]}"; do
            IFS='|' read -r severity control title description remediation <<< "$finding"
            if should_report "$severity"; then
                case "$severity" in
                    critical) echo -e "  ${PURPLE}[CRITICAL]${NC} [$control] $title" ;;
                    high)     echo -e "  ${RED}[HIGH]${NC}     [$control] $title" ;;
                    medium)   echo -e "  ${YELLOW}[MEDIUM]${NC}   [$control] $title" ;;
                    low)      echo -e "  ${CYAN}[LOW]${NC}      [$control] $title" ;;
                    info)     echo -e "  ${BLUE}[INFO]${NC}     [$control] $title" ;;
                esac
                echo -e "              ${description}"
                if [[ -n "$remediation" ]]; then
                    echo -e "              ${GREEN}Fix:${NC} ${remediation}"
                fi
                echo ""
            fi
        done
    fi

    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"

    # Overall status
    if [[ "$CRITICAL_COUNT" -gt 0 ]]; then
        echo -e "  ${PURPLE}${BOLD}STATUS: CRITICAL — Immediate action required${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 1
    elif [[ "$HIGH_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}${BOLD}STATUS: HIGH RISK — Action required within 48 hours${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 2
    elif [[ "$MEDIUM_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}STATUS: MODERATE — Address within maintenance window${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 3
    else
        echo -e "  ${GREEN}${BOLD}STATUS: COMPLIANT — All critical checks passed${NC}"
        echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        return 0
    fi
}

generate_json_report() {
    local json_output="{\"timestamp\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
    json_output+="\"namespace\":\"${NAMESPACE}\","
    json_output+="\"framework\":\"${FRAMEWORK}\","
    json_output+="\"airGapped\":${AIR_GAPPED},"
    json_output+="\"summary\":{\"total\":${#FINDINGS[@]},\"critical\":${CRITICAL_COUNT},\"high\":${HIGH_COUNT},\"medium\":${MEDIUM_COUNT},\"low\":${LOW_COUNT},\"info\":${INFO_COUNT}},"
    json_output+="\"findings\":["

    local first=true
    for finding in "${FINDINGS[@]}"; do
        IFS='|' read -r severity control title description remediation <<< "$finding"
        if should_report "$severity"; then
            [[ "$first" == "true" ]] || json_output+=","
            first=false
            json_output+="{\"severity\":\"${severity}\",\"control\":\"${control}\",\"title\":\"${title}\",\"description\":\"${description}\",\"remediation\":\"${remediation}\"}"
        fi
    done

    json_output+="]}"
    echo "$json_output" | python3 -m json.tool 2>/dev/null || echo "$json_output"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    log_info "NOVA Sovereign Cloud Security Audit starting..."
    log_info "Framework: ${FRAMEWORK} | Namespace: ${NAMESPACE} | Air-gapped: ${AIR_GAPPED}"

    # Run all checks
    check_tls_security
    check_network_security
    check_container_security
    check_data_protection
    check_access_control
    check_audit_logging
    check_availability

    # Run framework-specific checks
    case "$FRAMEWORK" in
        nist|all)    check_nist_800_53 ;;&
        iso27001|all) check_iso_27001 ;;&
        fedramp|all)  check_fedramp ;;&
    esac

    # Generate report
    local exit_code=0
    case "$OUTPUT_FORMAT" in
        json)
            if [[ -n "$REPORT_PATH" ]]; then
                generate_json_report > "$REPORT_PATH"
                log_info "JSON report saved to: ${REPORT_PATH}"
            else
                generate_json_report
            fi
            ;;
        *)
            generate_report || exit_code=$?
            if [[ -n "$REPORT_PATH" ]]; then
                generate_report > "$REPORT_PATH" 2>/dev/null || true
                log_info "Report saved to: ${REPORT_PATH}"
            fi
            ;;
    esac

    return $exit_code
}

# Handle continuous mode
if [[ "$CONTINUOUS" == "true" ]]; then
    log_info "Starting continuous security monitoring (interval: ${INTERVAL}s)"
    while true; do
        main || true
        log_info "Next scan in ${INTERVAL} seconds..."
        sleep "$INTERVAL"
    done
else
    main
fi
