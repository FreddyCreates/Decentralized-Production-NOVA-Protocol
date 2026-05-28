#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Cloud Deployment Orchestrator
# Complete deployment automation for governments, states, and enterprises
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./deploy.sh --environment gov-us --mode sovereign
#   ./deploy.sh --environment enterprise --mode federated --dry-run
#   ./deploy.sh --environment airgapped --mode sovereign --skip-validation
#
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_DIR="$(dirname "${SCRIPT_DIR}")"
readonly REPO_ROOT="$(dirname "${DEPLOY_DIR}")"
readonly VERSION="1.0.0"
readonly MIN_DOCKER_VERSION="24.0"
readonly MIN_K8S_VERSION="1.28"
readonly MIN_TERRAFORM_VERSION="1.7"
readonly MIN_HELM_VERSION="3.14"

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    GOLD=$'\033[38;5;178m'
    GREEN=$'\033[32m'
    CYAN=$'\033[36m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    DIM=$'\033[2m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    GOLD="" GREEN="" CYAN="" RED="" YELLOW="" DIM="" BOLD="" RESET=""
fi

# ── Logging ───────────────────────────────────────────────────────────────────
log() { echo -e "${GREEN}[$(date -u '+%H:%M:%S')]${RESET} $*"; }
log_info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_fatal() { echo -e "${RED}[FATAL]${RESET} $*" >&2; exit 1; }
log_step() { echo -e "\n${GOLD}═══ $* ═══${RESET}\n"; }

# ── Default Configuration ─────────────────────────────────────────────────────
ENVIRONMENT="enterprise"
MODE="sovereign"
DRY_RUN=false
SKIP_VALIDATION=false
SKIP_BACKUP=false
FORCE=false
VERBOSE=false
NAMESPACE="nova-sovereign"
DEPLOYMENT_NAME="nova-sovereign"
JURISDICTION="XX"
CLASSIFICATION="unclassified"
CLOUD_PROVIDER="private"
REPLICA_COUNT=3
ENABLE_TLS=true
ENABLE_MTLS=true
ENABLE_MONITORING=true
ENABLE_BACKUP=true
ENABLE_AIRGAPPED=false
TERRAFORM_DIR="${DEPLOY_DIR}/terraform"
KUBERNETES_DIR="${DEPLOY_DIR}/kubernetes"
DOCKER_DIR="${DEPLOY_DIR}/docker"

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}NOVA Protocol — Sovereign Cloud Deployment Orchestrator${RESET}

${CYAN}Usage:${RESET}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${RESET}
    --environment ENV     Deployment environment: gov-us, gov-eu, enterprise, airgapped
    --mode MODE           Deployment mode: sovereign, federated, edge
    --namespace NS        Kubernetes namespace (default: nova-sovereign)
    --name NAME           Deployment name (default: nova-sovereign)
    --jurisdiction JUR    ISO 3166-1 alpha-2 jurisdiction code (default: XX)
    --classification CLS  Classification: unclassified, cui, secret, top-secret
    --cloud PROVIDER      Cloud: aws-govcloud, azure-gov, gcp-assured, oci-gov, private
    --replicas N          Number of replicas (default: 3)
    --dry-run             Show what would be done without executing
    --skip-validation     Skip pre-deployment validation
    --skip-backup         Skip pre-deployment backup
    --force               Force deployment even with warnings
    --verbose             Enable verbose output
    --help                Show this help message

${CYAN}Environments:${RESET}
    gov-us        US Government (GovCloud, FedRAMP High, IL4/5)
    gov-eu        EU Government (GDPR compliant, data residency)
    enterprise    Enterprise private cloud
    airgapped     Air-gapped deployment (zero network)

${CYAN}Examples:${RESET}
    $(basename "$0") --environment gov-us --jurisdiction US --classification cui
    $(basename "$0") --environment enterprise --cloud private --replicas 5
    $(basename "$0") --environment airgapped --skip-validation --force

EOF
    exit 0
}

# ── Parse Arguments ───────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment) ENVIRONMENT="$2"; shift 2;;
            --mode) MODE="$2"; shift 2;;
            --namespace) NAMESPACE="$2"; shift 2;;
            --name) DEPLOYMENT_NAME="$2"; shift 2;;
            --jurisdiction) JURISDICTION="$2"; shift 2;;
            --classification) CLASSIFICATION="$2"; shift 2;;
            --cloud) CLOUD_PROVIDER="$2"; shift 2;;
            --replicas) REPLICA_COUNT="$2"; shift 2;;
            --dry-run) DRY_RUN=true; shift;;
            --skip-validation) SKIP_VALIDATION=true; shift;;
            --skip-backup) SKIP_BACKUP=true; shift;;
            --force) FORCE=true; shift;;
            --verbose) VERBOSE=true; shift;;
            --help|-h) usage;;
            *) log_error "Unknown option: $1"; usage;;
        esac
    done

    # Apply environment presets
    case "${ENVIRONMENT}" in
        gov-us)
            JURISDICTION="${JURISDICTION:-US}"
            CLASSIFICATION="${CLASSIFICATION:-cui}"
            CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws-govcloud}"
            REPLICA_COUNT="${REPLICA_COUNT:-5}"
            ENABLE_MTLS=true
            ;;
        gov-eu)
            JURISDICTION="${JURISDICTION:-EU}"
            CLASSIFICATION="${CLASSIFICATION:-unclassified}"
            CLOUD_PROVIDER="${CLOUD_PROVIDER:-private}"
            REPLICA_COUNT="${REPLICA_COUNT:-3}"
            ENABLE_MTLS=true
            ;;
        airgapped)
            ENABLE_AIRGAPPED=true
            CLOUD_PROVIDER="private"
            ;;
        enterprise)
            ;;
        *)
            log_warn "Unknown environment: ${ENVIRONMENT}, using enterprise defaults"
            ENVIRONMENT="enterprise"
            ;;
    esac
}

# ── Prerequisite Checks ──────────────────────────────────────────────────────

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command not found: $1"
        return 1
    fi
    return 0
}

version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

check_prerequisites() {
    log_step "Checking Prerequisites"
    local errors=0

    # Docker
    if check_command docker; then
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0")
        if version_gte "${docker_version}" "${MIN_DOCKER_VERSION}"; then
            log_info "Docker ${docker_version} ✓"
        else
            log_warn "Docker ${docker_version} < ${MIN_DOCKER_VERSION} (may have issues)"
        fi
    else
        log_warn "Docker not found (required for container builds)"
        ((errors++))
    fi

    # Kubernetes
    if check_command kubectl; then
        local k8s_version
        k8s_version=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/v//')
        log_info "kubectl ${k8s_version} ✓"
    else
        log_warn "kubectl not found (required for Kubernetes deployment)"
        ((errors++))
    fi

    # Helm
    if check_command helm; then
        local helm_version
        helm_version=$(helm version --short 2>/dev/null | sed 's/v//' | cut -d'+' -f1)
        log_info "Helm ${helm_version} ✓"
    else
        log_warn "Helm not found (required for Kubernetes deployment)"
        ((errors++))
    fi

    # Terraform
    if check_command terraform; then
        local tf_version
        tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version')
        log_info "Terraform ${tf_version} ✓"
    else
        log_warn "Terraform not found (required for IaC deployment)"
        ((errors++))
    fi

    # OpenSSL
    if check_command openssl; then
        local ssl_version
        ssl_version=$(openssl version 2>/dev/null | awk '{print $2}')
        log_info "OpenSSL ${ssl_version} ✓"
    else
        log_error "OpenSSL not found (required for certificate management)"
        ((errors++))
    fi

    # jq
    if check_command jq; then
        log_info "jq ✓"
    else
        log_error "jq not found (required for JSON processing)"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]] && [[ "${FORCE}" != "true" ]]; then
        log_fatal "Prerequisites check failed (${errors} issues). Use --force to override."
    fi

    log_info "Prerequisites check complete"
}

# ── Pre-deployment Validation ─────────────────────────────────────────────────

validate_cluster() {
    log_step "Validating Kubernetes Cluster"

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_fatal "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    fi
    log_info "Cluster connectivity ✓"

    # Check node count
    local node_count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [[ ${node_count} -lt ${REPLICA_COUNT} ]]; then
        log_warn "Cluster has ${node_count} nodes but ${REPLICA_COUNT} replicas requested"
    fi
    log_info "Cluster nodes: ${node_count}"

    # Check available resources
    local total_cpu total_memory
    total_cpu=$(kubectl top nodes 2>/dev/null | tail -n +2 | awk '{sum += $3} END {print sum}' || echo "unknown")
    total_memory=$(kubectl top nodes 2>/dev/null | tail -n +2 | awk '{sum += $5} END {print sum}' || echo "unknown")
    log_info "Cluster CPU usage: ${total_cpu}%"
    log_info "Cluster memory usage: ${total_memory}%"

    # Check storage classes
    local sc_count
    sc_count=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    if [[ ${sc_count} -eq 0 ]]; then
        log_warn "No storage classes found. Persistent volumes may fail."
    else
        log_info "Storage classes available: ${sc_count}"
    fi

    # Check if namespace already exists
    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_warn "Namespace '${NAMESPACE}' already exists"
        if [[ "${FORCE}" != "true" ]]; then
            log_info "Use --force to deploy into existing namespace"
        fi
    fi

    log_info "Cluster validation complete"
}

validate_security() {
    log_step "Validating Security Configuration"

    # Check if Pod Security Admission is available
    if kubectl api-resources | grep -q "podsecuritypolicies"; then
        log_info "Pod Security Policies available ✓"
    fi

    # Check for existing secrets that might conflict
    if kubectl get secret -n "${NAMESPACE}" 2>/dev/null | grep -q "nova-"; then
        log_warn "Existing NOVA secrets found in namespace. May be overwritten."
    fi

    # Validate TLS certificates if provided
    if [[ -f "${DEPLOY_DIR}/certs/server.crt" ]]; then
        local cert_expiry
        cert_expiry=$(openssl x509 -in "${DEPLOY_DIR}/certs/server.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
        log_info "Custom TLS certificate expires: ${cert_expiry}"
    fi

    log_info "Security validation complete"
}

# ── Deployment Functions ──────────────────────────────────────────────────────

generate_secrets() {
    log_step "Generating Secrets"

    local secrets_dir="${DEPLOY_DIR}/docker/secrets"
    mkdir -p "${secrets_dir}"

    if [[ ! -f "${secrets_dir}/db_password.txt" ]]; then
        openssl rand -base64 32 > "${secrets_dir}/db_password.txt"
        log_info "Generated database password"
    fi

    if [[ ! -f "${secrets_dir}/grafana_password.txt" ]]; then
        openssl rand -base64 24 > "${secrets_dir}/grafana_password.txt"
        log_info "Generated Grafana password"
    fi

    if [[ ! -f "${secrets_dir}/encryption_key.txt" ]]; then
        openssl rand -hex 32 > "${secrets_dir}/encryption_key.txt"
        log_info "Generated encryption key"
    fi

    # Generate backup encryption key
    if [[ ! -f "${secrets_dir}/backup_key.txt" ]]; then
        openssl rand -hex 64 > "${secrets_dir}/backup_key.txt"
        log_info "Generated backup encryption key"
    fi

    log_info "Secrets generation complete"
}

generate_certificates() {
    log_step "Generating TLS Certificates"

    local certs_dir="${DEPLOY_DIR}/certs"
    mkdir -p "${certs_dir}"

    if [[ -f "${certs_dir}/ca.crt" ]] && [[ "${FORCE}" != "true" ]]; then
        log_info "Certificates already exist (use --force to regenerate)"
        return
    fi

    # Generate Root CA
    log_info "Generating Root CA..."
    openssl genrsa -out "${certs_dir}/ca.key" 4096
    openssl req -new -x509 -key "${certs_dir}/ca.key" \
        -out "${certs_dir}/ca.crt" -days 3650 \
        -subj "/CN=NOVA Sovereign Root CA/O=NOVA Protocol/C=${JURISDICTION}"

    # Generate Server Certificate
    log_info "Generating Server Certificate..."
    openssl genrsa -out "${certs_dir}/server.key" 4096
    openssl req -new -key "${certs_dir}/server.key" \
        -out "${certs_dir}/server.csr" \
        -subj "/CN=nova-sovereign/O=NOVA Sovereign Node/C=${JURISDICTION}"

    # Create extensions file for SAN
    cat > "${certs_dir}/server.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = nova-sovereign
DNS.2 = nova-sovereign.${NAMESPACE}
DNS.3 = nova-sovereign.${NAMESPACE}.svc.cluster.local
DNS.4 = *.nova-sovereign.${NAMESPACE}.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF

    openssl x509 -req -in "${certs_dir}/server.csr" \
        -CA "${certs_dir}/ca.crt" -CAkey "${certs_dir}/ca.key" \
        -CAcreateserial -out "${certs_dir}/server.crt" \
        -days 365 -extfile "${certs_dir}/server.ext"

    # Generate Client Certificate (for mTLS)
    if [[ "${ENABLE_MTLS}" == "true" ]]; then
        log_info "Generating Client Certificate for mTLS..."
        openssl genrsa -out "${certs_dir}/client.key" 4096
        openssl req -new -key "${certs_dir}/client.key" \
            -out "${certs_dir}/client.csr" \
            -subj "/CN=nova-admin/O=NOVA Administration/C=${JURISDICTION}"

        cat > "${certs_dir}/client.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF

        openssl x509 -req -in "${certs_dir}/client.csr" \
            -CA "${certs_dir}/ca.crt" -CAkey "${certs_dir}/ca.key" \
            -CAcreateserial -out "${certs_dir}/client.crt" \
            -days 180 -extfile "${certs_dir}/client.ext"

        log_info "Client certificate generated (valid 180 days)"
    fi

    # Cleanup CSR and extension files
    rm -f "${certs_dir}"/*.csr "${certs_dir}"/*.ext "${certs_dir}"/*.srl

    # Set secure permissions
    chmod 600 "${certs_dir}"/*.key
    chmod 644 "${certs_dir}"/*.crt

    log_info "Certificate generation complete"
    log_info "  Root CA:     ${certs_dir}/ca.crt"
    log_info "  Server Cert: ${certs_dir}/server.crt"
    log_info "  Server Key:  ${certs_dir}/server.key"
    [[ "${ENABLE_MTLS}" == "true" ]] && log_info "  Client Cert: ${certs_dir}/client.crt"
}

deploy_docker() {
    log_step "Deploying via Docker Compose"

    cd "${DOCKER_DIR}"

    # Create .env from template
    if [[ ! -f ".env" ]] || [[ "${FORCE}" == "true" ]]; then
        cp sovereign.env.template .env
        sed -i "s/NOVA_DEPLOY_MODE=.*/NOVA_DEPLOY_MODE=${MODE}/" .env
        sed -i "s/NOVA_NETWORK=.*/NOVA_NETWORK=local/" .env
        sed -i "s/NOVA_ENABLE_TLS=.*/NOVA_ENABLE_TLS=${ENABLE_TLS}/" .env
        sed -i "s/NOVA_DATA_JURISDICTION=.*/NOVA_DATA_JURISDICTION=${JURISDICTION}/" .env
        log_info "Environment file configured"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: docker compose up -d"
        docker compose config
        return
    fi

    # Build images
    log_info "Building NOVA sovereign container..."
    docker compose build --no-cache

    # Deploy
    log_info "Starting sovereign stack..."
    docker compose up -d

    # Wait for health
    log_info "Waiting for services to be healthy..."
    local retries=30
    while [[ ${retries} -gt 0 ]]; do
        if docker compose ps | grep -q "healthy"; then
            log_info "Sovereign node is healthy ✓"
            break
        fi
        sleep 10
        ((retries--))
    done

    if [[ ${retries} -eq 0 ]]; then
        log_warn "Services may not be fully healthy yet. Check with: docker compose ps"
    fi

    log_info "Docker deployment complete"
}

deploy_kubernetes() {
    log_step "Deploying via Kubernetes (Helm)"

    cd "${KUBERNETES_DIR}"

    # Create namespace
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        kubectl create namespace "${NAMESPACE}"
        kubectl label namespace "${NAMESPACE}" \
            "pod-security.kubernetes.io/enforce=restricted" \
            "nova.sovereign/jurisdiction=${JURISDICTION}" \
            --overwrite
        log_info "Namespace '${NAMESPACE}' created with security labels"
    fi

    # Create TLS secrets
    local certs_dir="${DEPLOY_DIR}/certs"
    if [[ -f "${certs_dir}/server.crt" ]]; then
        kubectl create secret tls nova-tls-certs \
            --cert="${certs_dir}/server.crt" \
            --key="${certs_dir}/server.key" \
            -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic nova-ca \
            --from-file=ca.crt="${certs_dir}/ca.crt" \
            -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
        log_info "TLS secrets created"
    fi

    # Prepare values override
    local values_override="/tmp/nova-deploy-values.yaml"
    cat > "${values_override}" <<EOF
global:
  jurisdiction: "${JURISDICTION}"
  cloudProvider: "${CLOUD_PROVIDER}"
  classificationLevel: "${CLASSIFICATION}"

sovereign:
  replicaCount: ${REPLICA_COUNT}

tls:
  enabled: ${ENABLE_TLS}
  mtls:
    enabled: ${ENABLE_MTLS}

monitoring:
  enabled: ${ENABLE_MONITORING}

backup:
  enabled: ${ENABLE_BACKUP}

airgapped:
  enabled: ${ENABLE_AIRGAPPED}
EOF

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: helm upgrade --install"
        helm template "${DEPLOYMENT_NAME}" . -f "${values_override}" -n "${NAMESPACE}"
        return
    fi

    # Deploy with Helm
    helm upgrade --install "${DEPLOYMENT_NAME}" . \
        -f "${values_override}" \
        -n "${NAMESPACE}" \
        --wait \
        --timeout 10m

    log_info "Helm deployment complete"

    # Verify deployment
    kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${DEPLOYMENT_NAME}"
}

deploy_terraform() {
    log_step "Deploying via Terraform"

    cd "${TERRAFORM_DIR}"

    # Select tfvars based on environment
    local tfvars_file=""
    case "${ENVIRONMENT}" in
        gov-us) tfvars_file="environments/gov-us/terraform.tfvars";;
        gov-eu) tfvars_file="environments/gov-eu/terraform.tfvars";;
        enterprise) tfvars_file="environments/enterprise/terraform.tfvars";;
        airgapped) tfvars_file="environments/airgapped/terraform.tfvars";;
    esac

    # Create tfvars if not present
    if [[ ! -f "${tfvars_file}" ]]; then
        mkdir -p "$(dirname "${tfvars_file}")"
        cat > "${tfvars_file}" <<EOF
deployment_name      = "${DEPLOYMENT_NAME}"
namespace            = "${NAMESPACE}"
jurisdiction         = "${JURISDICTION}"
classification_level = "${CLASSIFICATION}"
cloud_provider       = "${CLOUD_PROVIDER}"
replica_count        = ${REPLICA_COUNT}
enable_airgapped     = ${ENABLE_AIRGAPPED}
enable_mtls          = ${ENABLE_MTLS}
backup_retention_days = 90
EOF
        log_info "Generated terraform.tfvars for ${ENVIRONMENT}"
    fi

    # Initialize Terraform
    terraform init -input=false

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Terraform plan:"
        terraform plan -var-file="${tfvars_file}" -input=false
        return
    fi

    # Apply
    terraform apply -var-file="${tfvars_file}" -input=false -auto-approve

    log_info "Terraform deployment complete"
    terraform output
}

# ── Post-Deployment ───────────────────────────────────────────────────────────

post_deployment_checks() {
    log_step "Post-Deployment Verification"

    local checks_passed=0
    local checks_total=0

    # Check 1: Pods running
    ((checks_total++))
    local running_pods
    running_pods=$(kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ ${running_pods} -ge 1 ]]; then
        log_info "✓ Pods running: ${running_pods}"
        ((checks_passed++))
    else
        log_error "✗ No pods running in namespace ${NAMESPACE}"
    fi

    # Check 2: Services available
    ((checks_total++))
    local services
    services=$(kubectl get svc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    if [[ ${services} -ge 1 ]]; then
        log_info "✓ Services available: ${services}"
        ((checks_passed++))
    else
        log_error "✗ No services found"
    fi

    # Check 3: Network policies
    ((checks_total++))
    local np_count
    np_count=$(kubectl get networkpolicies -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    if [[ ${np_count} -ge 1 ]]; then
        log_info "✓ Network policies: ${np_count}"
        ((checks_passed++))
    else
        log_warn "○ No network policies (may be expected for dev)"
    fi

    # Check 4: TLS secrets
    ((checks_total++))
    if kubectl get secret -n "${NAMESPACE}" nova-tls-certs &>/dev/null; then
        log_info "✓ TLS secrets configured"
        ((checks_passed++))
    else
        log_warn "○ TLS secrets not found"
    fi

    # Summary
    echo ""
    log_info "Verification: ${checks_passed}/${checks_total} checks passed"

    if [[ ${checks_passed} -eq ${checks_total} ]]; then
        log "All post-deployment checks passed ✓"
    elif [[ ${checks_passed} -ge $((checks_total / 2)) ]]; then
        log_warn "Some checks did not pass. Review the output above."
    else
        log_error "Multiple checks failed. Deployment may not be healthy."
    fi
}

print_summary() {
    log_step "Deployment Summary"

    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║  NOVA PROTOCOL — Sovereign Cloud Deployment Complete          ║${RESET}"
    echo -e "${BOLD}╠═══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "║  Environment:    ${GOLD}${ENVIRONMENT}${RESET}"
    echo -e "║  Mode:           ${GOLD}${MODE}${RESET}"
    echo -e "║  Jurisdiction:   ${GOLD}${JURISDICTION}${RESET}"
    echo -e "║  Classification: ${GOLD}${CLASSIFICATION}${RESET}"
    echo -e "║  Cloud:          ${GOLD}${CLOUD_PROVIDER}${RESET}"
    echo -e "║  Replicas:       ${GOLD}${REPLICA_COUNT}${RESET}"
    echo -e "║  Namespace:      ${GOLD}${NAMESPACE}${RESET}"
    echo -e "║  TLS:            ${GOLD}${ENABLE_TLS}${RESET}"
    echo -e "║  mTLS:           ${GOLD}${ENABLE_MTLS}${RESET}"
    echo -e "║  Air-gapped:     ${GOLD}${ENABLE_AIRGAPPED}${RESET}"
    echo -e "${BOLD}╠═══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "║  ${CYAN}Access Points:${RESET}"
    echo -e "║    Dashboard:    http://localhost:3000"
    echo -e "║    Canister API: http://localhost:8080"
    echo -e "║    Metrics:      http://localhost:9090"
    echo -e "║    Grafana:      http://localhost:3001"
    [[ "${ENABLE_TLS}" == "true" ]] && \
    echo -e "║    Sovereign API: https://localhost:8443"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${RESET}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo -e "${GOLD}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     NOVA PROTOCOL — Sovereign Cloud Deployment               ║"
    echo "║     Version: ${VERSION}                                         ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    parse_args "$@"

    log_info "Environment: ${ENVIRONMENT}"
    log_info "Mode: ${MODE}"
    log_info "Jurisdiction: ${JURISDICTION}"
    log_info "Classification: ${CLASSIFICATION}"

    # Phase 1: Prerequisites
    check_prerequisites

    # Phase 2: Validation
    if [[ "${SKIP_VALIDATION}" != "true" ]]; then
        validate_cluster
        validate_security
    fi

    # Phase 3: Generate secrets and certificates
    generate_secrets
    generate_certificates

    # Phase 4: Deploy based on available tools
    if check_command kubectl && check_command helm; then
        deploy_kubernetes
    elif check_command docker; then
        deploy_docker
    else
        log_fatal "No deployment method available. Need either kubectl+helm or docker."
    fi

    # Phase 5: Terraform (if available and IaC requested)
    if check_command terraform && [[ -d "${TERRAFORM_DIR}" ]]; then
        deploy_terraform
    fi

    # Phase 6: Post-deployment
    post_deployment_checks
    print_summary
}

main "$@"
