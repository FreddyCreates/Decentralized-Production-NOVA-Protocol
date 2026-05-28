# ═══════════════════════════════════════════════════════════════════════════════
# NOVA Cloud Platform — Multi-stage Dockerfile
# ═══════════════════════════════════════════════════════════════════════════════

# ── Build Stage ───────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /build
COPY package.json ./
COPY api/package.json ./api/
COPY scheduler/package.json ./scheduler/
COPY shared/package.json ./shared/
COPY cli/package.json ./cli/
RUN npm install --workspaces --include-workspace-root
COPY . .
RUN npm run build || true

# ── API Server ────────────────────────────────────────────────────────────────
FROM node:20-alpine AS api
RUN apk add --no-cache curl
WORKDIR /app
COPY --from=builder /build/api ./api
COPY --from=builder /build/shared ./shared
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package.json ./
WORKDIR /app/api
EXPOSE 4000
CMD ["node", "--loader", "ts-node/esm", "server.ts"]

# ── Scheduler ─────────────────────────────────────────────────────────────────
FROM node:20-alpine AS scheduler
WORKDIR /app
COPY --from=builder /build/scheduler ./scheduler
COPY --from=builder /build/shared ./shared
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package.json ./
WORKDIR /app/scheduler
CMD ["node", "--loader", "ts-node/esm", "index.ts"]
