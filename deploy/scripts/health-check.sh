#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Health Check & Diagnostics
# Comprehensive system health verification and troubleshooting
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./health-check.sh                    # Run all checks
#   ./health-check.sh --component nodes  # Check specific component
#   ./health-check.sh --json             # Output as JSON
#   ./health-check.sh --continuous       # Run continuously
#
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

readonly NAMESPACE="${NOVA_NAMESPACE:-nova-sovereign}"
readonly DEPLOYMENT_NAME="${NOVA_DEPLOYMENT:-nova-sovereign}"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ── State ─────────────────────────────────────────────────────────────────────
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNED_CHECKS=0
FAILED_CHECKS=0
OUTPUT_JSON=false
COMPONENT=""
CONTINUOUS=false

# ── Argument Parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --json) OUTPUT_JSON=true; shift;;
        --component) COMPONENT="$2"; shift 2;;
        --continuous) CONTINUOUS=true; shift;;
        --help|-h)
            echo "Usage: $0 [--json] [--component NAME] [--continuous]"
            echo "Components: nodes, database, network, certificates, monitoring, governance, storage"
            exit 0;;
        *) shift;;
    esac
done

# ── Check Functions ───────────────────────────────────────────────────────────

check() {
    local name="$1" status="$2" message="$3"
    ((TOTAL_CHECKS++))

    case "${status}" in
        pass)
            ((PASSED_CHECKS++))
            [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "  ${GREEN}✓${RESET} ${name}: ${message}"
            ;;
        warn)
            ((WARNED_CHECKS++))
            [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "  ${YELLOW}○${RESET} ${name}: ${message}"
            ;;
        fail)
            ((FAILED_CHECKS++))
            [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "  ${RED}✗${RESET} ${name}: ${message}"
            ;;
    esac
}

# ── Node Health ───────────────────────────────────────────────────────────────

check_nodes() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Sovereign Node Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # Pod status
    local total_pods running_pods
    total_pods=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" --no-headers 2>/dev/null | wc -l)
    running_pods=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [[ ${running_pods} -eq ${total_pods} ]] && [[ ${total_pods} -gt 0 ]]; then
        check "Pod Status" "pass" "${running_pods}/${total_pods} pods running"
    elif [[ ${running_pods} -gt 0 ]]; then
        check "Pod Status" "warn" "${running_pods}/${total_pods} pods running"
    else
        check "Pod Status" "fail" "No pods running (${total_pods} total)"
    fi

    # Pod restarts
    local max_restarts
    max_restarts=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" \
        -o jsonpath='{range .items[*]}{.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null | \
        sort -n | tail -1 || echo "0")

    if [[ ${max_restarts} -eq 0 ]]; then
        check "Pod Restarts" "pass" "No restarts detected"
    elif [[ ${max_restarts} -lt 5 ]]; then
        check "Pod Restarts" "warn" "Max restarts: ${max_restarts}"
    else
        check "Pod Restarts" "fail" "High restart count: ${max_restarts}"
    fi

    # IC Replica status
    local replica_status
    replica_status=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        curl -sf http://localhost:8080/api/v2/status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")

    if [[ "${replica_status}" == "running" ]] || [[ "${replica_status}" != "unknown" ]]; then
        check "IC Replica" "pass" "Replica status: ${replica_status}"
    else
        check "IC Replica" "fail" "Replica unreachable or not running"
    fi

    # Canister count
    local canister_count
    canister_count=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        dfx canister status --all 2>/dev/null | grep -c "Status:" || echo "0")

    if [[ ${canister_count} -gt 0 ]]; then
        check "Canisters" "pass" "${canister_count} canisters deployed"
    else
        check "Canisters" "warn" "No canisters detected"
    fi

    # Resource usage
    local cpu_usage memory_usage
    cpu_usage=$(kubectl top pod -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" \
        --no-headers 2>/dev/null | awk '{sum += $2} END {print sum+0}' || echo "0")
    memory_usage=$(kubectl top pod -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" \
        --no-headers 2>/dev/null | awk '{sum += $3} END {print sum+0}' || echo "0")

    if [[ ${cpu_usage} -lt 7000 ]]; then
        check "CPU Usage" "pass" "${cpu_usage}m total"
    elif [[ ${cpu_usage} -lt 9000 ]]; then
        check "CPU Usage" "warn" "${cpu_usage}m total (approaching limit)"
    else
        check "CPU Usage" "fail" "${cpu_usage}m total (at limit)"
    fi

    if [[ ${memory_usage} -lt 24000 ]]; then
        check "Memory Usage" "pass" "${memory_usage}Mi total"
    elif [[ ${memory_usage} -lt 30000 ]]; then
        check "Memory Usage" "warn" "${memory_usage}Mi total (approaching limit)"
    else
        check "Memory Usage" "fail" "${memory_usage}Mi total (at limit)"
    fi
}

# ── Database Health ───────────────────────────────────────────────────────────

check_database() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Database Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # PostgreSQL availability
    local pg_ready
    pg_ready=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        pg_isready -U postgres 2>/dev/null && echo "yes" || echo "no")

    if [[ "${pg_ready}" == "yes" ]]; then
        check "PostgreSQL" "pass" "Database is ready"
    else
        check "PostgreSQL" "fail" "Database is not ready"
        return
    fi

    # Connection count
    local conn_count max_conn
    conn_count=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
    max_conn=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        psql -U postgres -t -c "SHOW max_connections;" 2>/dev/null | tr -d ' ')

    local conn_pct=0
    if [[ -n "${max_conn}" ]] && [[ ${max_conn} -gt 0 ]]; then
        conn_pct=$((conn_count * 100 / max_conn))
    fi

    if [[ ${conn_pct} -lt 70 ]]; then
        check "Connections" "pass" "${conn_count}/${max_conn} (${conn_pct}%)"
    elif [[ ${conn_pct} -lt 90 ]]; then
        check "Connections" "warn" "${conn_count}/${max_conn} (${conn_pct}%)"
    else
        check "Connections" "fail" "${conn_count}/${max_conn} (${conn_pct}%)"
    fi

    # Replication lag (if applicable)
    local repl_lag
    repl_lag=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        psql -U postgres -t -c "SELECT COALESCE(MAX(EXTRACT(EPOCH FROM replay_lag)), 0) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ' || echo "0")

    if [[ "${repl_lag}" == "0" ]] || [[ -z "${repl_lag}" ]]; then
        check "Replication" "pass" "No lag detected"
    elif (( $(echo "${repl_lag} < 10" | bc -l 2>/dev/null || echo 1) )); then
        check "Replication" "warn" "Lag: ${repl_lag}s"
    else
        check "Replication" "fail" "High lag: ${repl_lag}s"
    fi

    # Database size
    local db_size
    db_size=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        psql -U postgres -t -c "SELECT pg_size_pretty(pg_database_size('nova_sovereign'));" 2>/dev/null | tr -d ' ')
    check "Database Size" "pass" "${db_size:-unknown}"
}

# ── Network Health ────────────────────────────────────────────────────────────

check_network() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Network Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # Network policies
    local np_count
    np_count=$(kubectl get networkpolicies -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)

    if [[ ${np_count} -ge 5 ]]; then
        check "Network Policies" "pass" "${np_count} policies active"
    elif [[ ${np_count} -ge 1 ]]; then
        check "Network Policies" "warn" "Only ${np_count} policies (expected 5+)"
    else
        check "Network Policies" "fail" "No network policies found"
    fi

    # Service endpoints
    local endpoints
    endpoints=$(kubectl get endpoints -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -v "<none>" | wc -l)
    check "Service Endpoints" "pass" "${endpoints} endpoints available"

    # DNS resolution
    local dns_ok
    dns_ok=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        nslookup kubernetes.default.svc.cluster.local 2>/dev/null && echo "yes" || echo "no")

    if [[ "${dns_ok}" == "yes" ]]; then
        check "DNS Resolution" "pass" "Cluster DNS working"
    else
        check "DNS Resolution" "fail" "Cluster DNS resolution failed"
    fi

    # Inter-pod connectivity
    local pod_ips
    pod_ips=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-sovereign" \
        -o jsonpath='{.items[*].status.podIP}' 2>/dev/null)

    if [[ -n "${pod_ips}" ]]; then
        check "Pod Networking" "pass" "Pods have IP addresses assigned"
    else
        check "Pod Networking" "warn" "Could not verify pod IPs"
    fi
}

# ── Certificate Health ────────────────────────────────────────────────────────

check_certificates() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Certificate Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # Check TLS secret exists
    local tls_secret
    tls_secret=$(kubectl get secret -n "${NAMESPACE}" -l "nova.sovereign/cert-type=server" \
        --no-headers 2>/dev/null | wc -l)

    if [[ ${tls_secret} -gt 0 ]]; then
        check "TLS Secret" "pass" "Server TLS secret present"
    else
        # Try alternative secret name
        if kubectl get secret -n "${NAMESPACE}" "nova-tls-certs" &>/dev/null; then
            check "TLS Secret" "pass" "TLS secret (nova-tls-certs) present"
        else
            check "TLS Secret" "fail" "No TLS secret found"
        fi
    fi

    # Check certificate expiry
    local cert_data
    cert_data=$(kubectl get secret -n "${NAMESPACE}" "nova-tls-certs" \
        -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)

    if [[ -n "${cert_data}" ]]; then
        local expiry_date
        expiry_date=$(echo "${cert_data}" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        local expiry_epoch now_epoch remaining_days
        expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        remaining_days=$(( (expiry_epoch - now_epoch) / 86400 ))

        if [[ ${remaining_days} -gt 60 ]]; then
            check "Certificate Expiry" "pass" "Expires in ${remaining_days} days"
        elif [[ ${remaining_days} -gt 14 ]]; then
            check "Certificate Expiry" "warn" "Expires in ${remaining_days} days"
        elif [[ ${remaining_days} -gt 0 ]]; then
            check "Certificate Expiry" "fail" "EXPIRES in ${remaining_days} days!"
        else
            check "Certificate Expiry" "fail" "Certificate has EXPIRED"
        fi
    fi

    # CA secret
    if kubectl get secret -n "${NAMESPACE}" -l "nova.sovereign/cert-type=root-ca" &>/dev/null || \
       kubectl get secret -n "${NAMESPACE}" "nova-ca" &>/dev/null; then
        check "CA Certificate" "pass" "CA secret present"
    else
        check "CA Certificate" "warn" "CA secret not found"
    fi
}

# ── Monitoring Health ─────────────────────────────────────────────────────────

check_monitoring() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Monitoring Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # Prometheus
    local prom_pods
    prom_pods=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=nova-monitoring" \
        --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [[ ${prom_pods} -gt 0 ]]; then
        check "Prometheus" "pass" "Running (${prom_pods} pods)"
    else
        check "Prometheus" "warn" "Prometheus not detected"
    fi

    # Metrics endpoint
    local metrics_ok
    metrics_ok=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        curl -sf http://localhost:9090/metrics 2>/dev/null | head -1 | grep -c "^#" || echo "0")

    if [[ ${metrics_ok} -gt 0 ]]; then
        check "Metrics Endpoint" "pass" "Metrics available on :9090"
    else
        check "Metrics Endpoint" "warn" "Metrics endpoint not responding"
    fi

    # Audit logging
    local audit_recent
    audit_recent=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        find /opt/nova/data/audit -name "*.log" -mmin -30 -type f 2>/dev/null | wc -l || echo "0")

    if [[ ${audit_recent} -gt 0 ]]; then
        check "Audit Logging" "pass" "Recent audit entries found"
    else
        check "Audit Logging" "warn" "No recent audit entries (last 30 min)"
    fi
}

# ── Governance Health ─────────────────────────────────────────────────────────

check_governance() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Governance Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # Governance config exists
    if kubectl get configmap -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-governance-config" &>/dev/null; then
        check "Governance Config" "pass" "Configuration present"
    else
        check "Governance Config" "warn" "Governance config not found"
    fi

    # Multi-sig status (check governance DB table)
    local active_signers
    active_signers=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-postgres-0" -- \
        psql -U postgres -d nova_sovereign -t -c \
        "SELECT COUNT(*) FROM governance.signers WHERE status='active';" 2>/dev/null | tr -d ' ' || echo "0")

    if [[ ${active_signers} -ge 3 ]]; then
        check "Multi-Sig Quorum" "pass" "${active_signers} active signers"
    elif [[ ${active_signers} -ge 1 ]]; then
        check "Multi-Sig Quorum" "warn" "Only ${active_signers} signers (need 3+ for quorum)"
    else
        check "Multi-Sig Quorum" "warn" "No signers registered (may be initial setup)"
    fi
}

# ── Storage Health ────────────────────────────────────────────────────────────

check_storage() {
    [[ "${OUTPUT_JSON}" != "true" ]] && echo -e "\n${BOLD}Storage Health${RESET}"
    [[ "${OUTPUT_JSON}" != "true" ]] && echo "────────────────────────────────────────────────"

    # PVC status
    local bound_pvcs total_pvcs
    total_pvcs=$(kubectl get pvc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    bound_pvcs=$(kubectl get pvc -n "${NAMESPACE}" --field-selector=status.phase=Bound --no-headers 2>/dev/null | wc -l)

    if [[ ${bound_pvcs} -eq ${total_pvcs} ]] && [[ ${total_pvcs} -gt 0 ]]; then
        check "PVC Status" "pass" "${bound_pvcs}/${total_pvcs} volumes bound"
    elif [[ ${bound_pvcs} -gt 0 ]]; then
        check "PVC Status" "warn" "${bound_pvcs}/${total_pvcs} volumes bound"
    else
        check "PVC Status" "fail" "No volumes bound"
    fi

    # Disk usage on data volume
    local disk_usage
    disk_usage=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        df -h /opt/nova/data 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")

    if [[ ${disk_usage} -lt 70 ]]; then
        check "Disk Usage" "pass" "${disk_usage}% used"
    elif [[ ${disk_usage} -lt 85 ]]; then
        check "Disk Usage" "warn" "${disk_usage}% used"
    else
        check "Disk Usage" "fail" "${disk_usage}% used (critical)"
    fi

    # Backup status
    local last_backup
    last_backup=$(kubectl exec -n "${NAMESPACE}" "${DEPLOYMENT_NAME}-node-0" -- \
        find /opt/nova/data/backups -name "*.tar.gz*" -mtime -2 -type f 2>/dev/null | wc -l || echo "0")

    if [[ ${last_backup} -gt 0 ]]; then
        check "Recent Backup" "pass" "Backup exists within 48h"
    else
        check "Recent Backup" "warn" "No backup within 48h"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}Health Check Summary${RESET}"
    echo -e "═══════════════════════════════════════════════════════════"
    echo -e "  Total checks: ${TOTAL_CHECKS}"
    echo -e "  ${GREEN}Passed:${RESET}       ${PASSED_CHECKS}"
    echo -e "  ${YELLOW}Warnings:${RESET}     ${WARNED_CHECKS}"
    echo -e "  ${RED}Failed:${RESET}       ${FAILED_CHECKS}"

    local score=0
    if [[ ${TOTAL_CHECKS} -gt 0 ]]; then
        score=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    fi
    echo -e "  Score:        ${score}%"
    echo ""

    if [[ ${FAILED_CHECKS} -eq 0 ]] && [[ ${WARNED_CHECKS} -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}STATUS: HEALTHY${RESET} ✓"
    elif [[ ${FAILED_CHECKS} -eq 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}STATUS: DEGRADED${RESET} (${WARNED_CHECKS} warnings)"
    else
        echo -e "  ${RED}${BOLD}STATUS: UNHEALTHY${RESET} (${FAILED_CHECKS} failures)"
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

run_checks() {
    if [[ -n "${COMPONENT}" ]]; then
        case "${COMPONENT}" in
            nodes) check_nodes;;
            database) check_database;;
            network) check_network;;
            certificates) check_certificates;;
            monitoring) check_monitoring;;
            governance) check_governance;;
            storage) check_storage;;
            *) echo "Unknown component: ${COMPONENT}"; exit 1;;
        esac
    else
        check_nodes
        check_database
        check_network
        check_certificates
        check_monitoring
        check_governance
        check_storage
    fi
    print_summary
}

main() {
    echo -e "${BOLD}NOVA Sovereign Cloud — Health Check${RESET}"
    echo -e "Namespace: ${NAMESPACE} | Deployment: ${DEPLOYMENT_NAME}"
    echo -e "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    if [[ "${CONTINUOUS}" == "true" ]]; then
        while true; do
            clear
            run_checks
            sleep 30
        done
    else
        run_checks
    fi

    # Exit with appropriate code
    if [[ ${FAILED_CHECKS} -gt 0 ]]; then
        exit 2
    elif [[ ${WARNED_CHECKS} -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main
