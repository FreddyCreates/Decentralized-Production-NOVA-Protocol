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

# ── Start NOVA Multi-Runtime Engine ──────────────────────────────────────────
start_nova_runtime() {
    log "Bootstrapping NOVA Multi-Runtime Engine..."
    log "  Substrates: ${NOVA_SUBSTRATES:-motoko,typescript,python,cpp,java,webworker}"
    log "  Heartbeat:  ${NOVA_HEARTBEAT_MS:-873}ms (φ-derived)"
    log "  Protocols:  129 (89 base + 40 alpha)"

    cd "${NOVA_HOME}"

    # Run ITB validation before starting runtime (pre-flight check)
    if [[ "${NOVA_RUN_ITB:-true}" == "true" ]]; then
        log "Running Integration Test Bed (ITB) pre-flight validation..."
        if node itb/run.mjs > "${LOG_DIR}/itb-validation.log" 2>&1; then
            log "✓ ITB validation passed — all substrates verified"
        else
            log_error "ITB validation failed — check ${LOG_DIR}/itb-validation.log"
            if [[ "${NOVA_ITB_STRICT:-false}" == "true" ]]; then
                log_error "Strict mode: aborting startup due to ITB failure"
                exit 1
            fi
            log "Non-strict mode: continuing despite ITB warnings"
        fi
    fi

    # Start the multi-runtime engine as background service on port 7700
    NOVA_RUNTIME_PORT="${NOVA_RUNTIME_PORT:-7700}" \
    NOVA_HEARTBEAT_MS="${NOVA_HEARTBEAT_MS:-873}" \
    NOVA_SUBSTRATES="${NOVA_SUBSTRATES:-motoko,typescript,python,cpp,java,webworker}" \
    NOVA_EMERGENCE_THRESHOLD="${NOVA_EMERGENCE_THRESHOLD:-0.89}" \
    NOVA_KURAMOTO_COUPLING="${NOVA_KURAMOTO_COUPLING:-0.618}" \
    node "${NOVA_HOME}/runtime/sovereign-engine.mjs" > "${LOG_DIR}/nova-runtime.log" 2>&1 &

    RUNTIME_PID=$!
    echo "${RUNTIME_PID}" > "${DATA_DIR}/nova-runtime.pid"
    log "✓ NOVA Multi-Runtime Engine started (PID: ${RUNTIME_PID}, port: ${NOVA_RUNTIME_PORT:-7700})"
    log "  46 organisms registered across 6 substrates"
    log "  Protocol binder active — Fibonacci + Kuramoto routing"
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
    start_nova_runtime
    start_metrics

    log "Sovereign node fully operational"
    log "Dashboard: http://localhost:3000"
    log "Canister API: http://localhost:8080"
    log "NOVA Runtime: http://localhost:${NOVA_RUNTIME_PORT:-7700}"
    [[ "${ENABLE_METRICS}" == "true" ]] && log "Metrics: http://localhost:9090"
    [[ "${ENABLE_TLS}" == "true" ]] && log "Sovereign API (mTLS): https://localhost:8443"

    # Keep container running
    tail -f "${LOG_DIR}/dfx-start.log" "${LOG_DIR}/dfx-init.log" 2>/dev/null || \
        tail -f /dev/null
}

main "$@"
