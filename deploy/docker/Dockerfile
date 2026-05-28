# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Protocol — Sovereign Cloud Container
# Deployable by governments, states, and enterprises in air-gapped environments
# ═══════════════════════════════════════════════════════════════════════════════

# Stage 1: Build TypeScript SDK & Frontend
FROM node:20-alpine AS ts-builder
WORKDIR /build
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci --ignore-scripts
COPY src/organism ./src/organism
COPY src/frontend ./src/frontend
RUN npx tsc --project tsconfig.json || true

# Stage 2: Build Rust Canisters (SSN modules)
FROM rust:1.78-slim AS rust-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
RUN rustup target add wasm32-unknown-unknown
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src/organisms/ssn_work ./src/organisms/ssn_work
COPY src/organisms/ssn_trust ./src/organisms/ssn_trust
COPY src/organisms/ssn_gov ./src/organisms/ssn_gov
RUN cargo build --release --target wasm32-unknown-unknown

# Stage 3: Runtime — Sovereign Node
FROM ubuntu:24.04 AS runtime

LABEL org.opencontainers.image.title="NOVA Protocol Sovereign Node"
LABEL org.opencontainers.image.description="Sovereign cloud-deployable NOVA Protocol for governments and enterprises"
LABEL org.opencontainers.image.vendor="Casa de Medina"
LABEL org.opencontainers.image.version="1.0.0"

# Security: run as non-root
RUN groupadd -r nova && useradd -r -g nova -d /opt/nova -s /bin/bash nova

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    openssl \
    libssl3 \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install DFX (Internet Computer SDK) for local replica
RUN curl -fsSL https://internetcomputer.org/install.sh | bash
ENV PATH="/root/.local/share/dfx/bin:${PATH}"

# Install Julia for cognitive engines
RUN curl -fsSL https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.4-linux-x86_64.tar.gz | \
    tar -xz -C /opt && ln -s /opt/julia-1.10.4/bin/julia /usr/local/bin/julia

# Install Node.js runtime for SDK
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Application directory
WORKDIR /opt/nova
RUN chown -R nova:nova /opt/nova

# Copy built artifacts
COPY --from=ts-builder /build/.nova/build ./sdk-build
COPY --from=rust-builder /build/target/wasm32-unknown-unknown/release/*.wasm ./wasm/

# Copy source and configuration
COPY src/organisms ./src/organisms
COPY engines ./engines
COPY protocols ./protocols
COPY dfx.json nova.json sns_init.yaml ./
COPY deploy/docker/entrypoint.sh /opt/nova/entrypoint.sh
COPY deploy/docker/sovereign.env.template /opt/nova/sovereign.env.template

RUN chmod +x /opt/nova/entrypoint.sh

# Sovereign configuration volume
VOLUME ["/opt/nova/data", "/opt/nova/config", "/opt/nova/keys"]

# Ports:
# 8080  - DFX local replica (canister HTTP)
# 4943  - DFX replica management
# 3000  - NOVA Dashboard / Admin Terminal
# 9090  - Metrics (Prometheus-compatible)
# 8443  - Sovereign API (mTLS)
EXPOSE 8080 4943 3000 9090 8443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/v2/status || exit 1

USER nova
ENTRYPOINT ["/opt/nova/entrypoint.sh"]
CMD ["--mode", "sovereign"]
