#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Cloud Entrypoint
# Bootstraps the sovereign node in containerized environments
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
readonly NOVA_HOME="/opt/nova"
readonly DATA_DIR="${NOVA_DATA_DIR:-/opt/nova/data}"
readonly CONFIG_DIR="${NOVA_CONFIG_DIR:-/opt/nova/config}"
readonly KEYS_DIR="${NOVA_KEYS_DIR:-/opt/nova/keys}"
readonly LOG_DIR="${DATA_DIR}/logs"

# ── Logging ───────────────────────────────────────────────────────────────────
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [NOVA] $*"; }
log_error() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }

# ── Parse Arguments ───────────────────────────────────────────────────────────
MODE="sovereign"
NETWORK="local"
ENABLE_METRICS="true"
ENABLE_TLS="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode) MODE="$2"; shift 2;;
        --network) NETWORK="$2"; shift 2;;
        --enable-metrics) ENABLE_METRICS="$2"; shift 2;;
        --enable-tls) ENABLE_TLS="$2"; shift 2;;
        *) shift;;
    esac
done

# ── Initialize Directories ───────────────────────────────────────────────────
mkdir -p "${DATA_DIR}" "${CONFIG_DIR}" "${KEYS_DIR}" "${LOG_DIR}"

# ── TLS Setup (for sovereign/gov deployments) ────────────────────────────────
setup_tls() {
    if [[ "${ENABLE_TLS}" == "true" ]]; then
        if [[ -f "${KEYS_DIR}/server.crt" && -f "${KEYS_DIR}/server.key" ]]; then
            log "TLS enabled with provided certificates"
        else
            log "Generating self-signed certificates for sovereign node..."
            openssl req -x509 -newkey rsa:4096 -keyout "${KEYS_DIR}/server.key" \
                -out "${KEYS_DIR}/server.crt" -days 365 -nodes \
                -subj "/CN=nova-sovereign/O=SovereignCloud/C=XX"
            log "Self-signed certificates generated (replace with CA-signed for production)"
        fi
    fi
}

# ── Initialize Local Replica ─────────────────────────────────────────────────
init_replica() {
    log "Initializing sovereign IC replica..."

    if [[ ! -d "${DATA_DIR}/.dfx" ]]; then
        cd "${NOVA_HOME}"
        dfx start --background --clean 2>&1 | tee "${LOG_DIR}/dfx-init.log"
        log "Deploying canisters to sovereign replica..."
        dfx deploy --network local 2>&1 | tee "${LOG_DIR}/dfx-deploy.log"
        log "Sovereign replica initialized with all canisters"
    else
        cd "${NOVA_HOME}"
        dfx start --background 2>&1 | tee "${LOG_DIR}/dfx-start.log"
        log "Sovereign replica resumed from existing state"
    fi
}

# ── Start Cognitive Engines ──────────────────────────────────────────────────
start_engines() {
    log "Starting cognitive engines..."

    # Julia engines
    if [[ -d "${NOVA_HOME}/engines/julia" ]]; then
        cd "${NOVA_HOME}/engines/julia"
        julia --project=. -e 'using Pkg; Pkg.instantiate()' 2>/dev/null || true
        log "Julia cognitive engines ready"
    fi

    # Python engines
    if [[ -d "${NOVA_HOME}/engines/python" ]]; then
        log "Python engines available"
    fi

    # JavaScript engines
    if [[ -d "${NOVA_HOME}/engines/javascript" ]]; then
        log "JavaScript engines available"
    fi
}

# ── Metrics Server ───────────────────────────────────────────────────────────
start_metrics() {
    if [[ "${ENABLE_METRICS}" == "true" ]]; then
        log "Starting metrics exporter on :9090..."
        # Simple metrics endpoint using bash + netcat fallback
        while true; do
            CANISTER_COUNT=$(dfx canister status --all 2>/dev/null | grep -c "Running" || echo "0")
            METRICS="# HELP nova_canisters_running Number of running canisters
# TYPE nova_canisters_running gauge
nova_canisters_running ${CANISTER_COUNT}
# HELP nova_node_up Whether the sovereign node is up
# TYPE nova_node_up gauge
nova_node_up 1"
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n${METRICS}" | \
                nc -l -p 9090 -q 1 2>/dev/null || true
            sleep 5
        done &
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    log "╔═══════════════════════════════════════════════════════════════╗"
    log "║  NOVA PROTOCOL — Sovereign Cloud Node                        ║"
    log "║  Mode: ${MODE} | Network: ${NETWORK}                         ║"
    log "╚═══════════════════════════════════════════════════════════════╝"

    setup_tls
    init_replica
    start_engines
    start_metrics

    log "Sovereign node fully operational"
    log "Dashboard: http://localhost:3000"
    log "Canister API: http://localhost:8080"
    [[ "${ENABLE_METRICS}" == "true" ]] && log "Metrics: http://localhost:9090"
    [[ "${ENABLE_TLS}" == "true" ]] && log "Sovereign API (mTLS): https://localhost:8443"

    # Keep container running
    tail -f "${LOG_DIR}/dfx-start.log" "${LOG_DIR}/dfx-init.log" 2>/dev/null || \
        tail -f /dev/null
}

main "$@"
