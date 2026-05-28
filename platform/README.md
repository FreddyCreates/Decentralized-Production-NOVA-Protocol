# NOVA Cloud Platform

**Your fly.io. Your infrastructure. Sovereign edge cloud.**

This is the actual platform — the control plane, CLI, scheduler, and proxy that lets you (and anyone you grant access) deploy applications to YOUR sovereign infrastructure.

---

## Quick Start

### 1. Start the Platform

```bash
cd platform
docker compose up -d
```

This boots:
- **API Server** on `localhost:4000` — the control plane
- **Scheduler** — places containers on your nodes (φ-weighted)
- **Proxy** (Traefik) on `localhost:80/443` — routes traffic to apps
- **Registry** on `localhost:5000` — stores container images
- **Database** (Postgres) — production state store

### 2. Install the CLI

```bash
cd platform/cli
npm install
npm link
```

Now you have `nova-cloud` available globally.

### 3. Create Your Account

```bash
nova-cloud auth signup
```

### 4. Launch an App

```bash
# Interactive setup (like `fly launch`)
nova-cloud launch

# Or manually:
nova-cloud apps create my-app
nova-cloud deploy --image nginx:latest
```

### 5. Manage Your App

```bash
# Check status
nova-cloud status

# Scale up
nova-cloud scale count 3

# Set secrets
nova-cloud secrets set DATABASE_URL=postgres://... API_KEY=sk-...

# View logs
nova-cloud logs -f

# List machines
nova-cloud machines list

# See regions
nova-cloud regions
```

---

## CLI Reference

| Command | Description |
|---------|-------------|
| `nova-cloud auth signup` | Create account |
| `nova-cloud auth login` | Log in |
| `nova-cloud auth whoami` | Current user |
| `nova-cloud apps create <name>` | Create app |
| `nova-cloud apps list` | List all apps |
| `nova-cloud apps info` | App details |
| `nova-cloud apps destroy <name>` | Delete app |
| `nova-cloud launch` | Interactive app setup |
| `nova-cloud init` | Create nova.toml |
| `nova-cloud deploy` | Deploy current app |
| `nova-cloud deploy --image <img>` | Deploy specific image |
| `nova-cloud scale count <n>` | Scale machines |
| `nova-cloud secrets list` | List secrets |
| `nova-cloud secrets set K=V` | Set secret |
| `nova-cloud secrets unset K` | Remove secret |
| `nova-cloud logs` | View logs |
| `nova-cloud logs -f` | Follow logs |
| `nova-cloud status` | App status + machines |
| `nova-cloud machines list` | List machines |
| `nova-cloud machines stop <id>` | Stop machine |
| `nova-cloud machines start <id>` | Start machine |
| `nova-cloud regions` | Available regions |

---

## nova.toml

Every app has a `nova.toml` config file (like `fly.toml`):

```toml
app = "my-app"
primary_region = "sov-1"
kill_signal = "SIGINT"
kill_timeout = 5

[build]
  dockerfile = "Dockerfile"

[deploy]
  strategy = "rolling"

[env]
  NODE_ENV = "production"

[[services]]
  internal_port = 8080
  protocol = "tcp"
  auto_stop = true
  auto_start = true

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [services.concurrency]
    type = "requests"
    hard_limit = 250
    soft_limit = 200

[scaling]
  min_machines = 1
  max_machines = 10
  auto_scale = true
```

---

## API Reference

Base URL: `http://localhost:4000/v1`

All authenticated requests need: `Authorization: ******

### Apps
- `GET /v1/apps` — List apps
- `POST /v1/apps` — Create app (`{ app_name, region }`)
- `GET /v1/apps/:name` — Get app
- `DELETE /v1/apps/:name` — Destroy app
- `POST /v1/apps/:name/scale` — Scale (`{ count, region }`)

### Deployments
- `POST /v1/deployments` — Deploy (`{ app_name, image, strategy, definition }`)
- `GET /v1/deployments/:appName` — List releases
- `POST /v1/deployments/:appName/rollback` — Rollback (`{ version }`)

### Machines
- `GET /v1/machines?app=name` — List machines
- `GET /v1/machines/:id` — Get machine
- `POST /v1/machines/:id/stop` — Stop
- `POST /v1/machines/:id/start` — Start
- `DELETE /v1/machines/:id` — Destroy

### Secrets
- `GET /v1/secrets/:appName` — List secrets
- `POST /v1/secrets/:appName` — Set secrets (`{ secrets: { K: V } }`)
- `DELETE /v1/secrets/:appName/:name` — Delete secret

### Logs
- `GET /v1/logs/:appName` — Get logs (`?limit=100&level=error&region=sov-1`)
- `WS /ws/logs?app=name` — Live log stream

### Regions
- `GET /v1/regions` — List regions

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NOVA CLOUD PLATFORM                            │
│                  (Your fly.io equivalent)                         │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │   CLI   │         │   API   │         │  Proxy  │
    │nova-cloud│        │  :4000  │         │ Traefik │
    └────┬────┘         └────┬────┘         └────┬────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │    Scheduler       │
                    │  (φ-weighted       │
                    │   placement)       │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
         ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
         │  Node   │    │  Node   │    │  Node   │
         │ sov-1   │    │ edge-us │    │ edge-eu │
         │(Docker) │    │(Docker) │    │(Docker) │
         └─────────┘    └─────────┘    └─────────┘
              │               │               │
         ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
         │ Your    │    │ Your    │    │ Your    │
         │  Apps   │    │  Apps   │    │  Apps   │
         └─────────┘    └─────────┘    └─────────┘
```

---

## Sovereign Differentiators (vs fly.io)

| Feature | fly.io | NOVA Cloud |
|---------|--------|------------|
| Infrastructure | Their servers | YOUR servers |
| Data sovereignty | Trust them | Trust yourself |
| Placement algo | Proprietary | φ-weighted (open) |
| Regions | Fixed | Add your own |
| Pricing | Per-use | You control |
| AI integration | None | Full NOVA organism layer |
| Governance | Their terms | Your protocol |
| Source | Closed | Sovereign open |

---

## Adding Regions (Nodes)

To add a new edge node:

1. Provision a server with Docker installed
2. Connect it to the platform network
3. Register it with the scheduler:

```typescript
scheduler.registerNode({
  id: 'node_custom_01',
  name: 'my-datacenter-1',
  region: 'edge-custom',
  docker: new Docker({ host: '10.0.0.5', port: 2376 }),
  capacity: { cpus: 16, memory_mb: 32768 },
  used: { cpus: 0, memory_mb: 0 },
});
```

---

## Production Deployment

For production, integrate with the existing NOVA sovereign infrastructure:

```bash
# Use the full sovereign stack alongside the platform
docker compose -f ../deploy/docker/docker-compose.yml \
               -f docker-compose.yml \
               up -d
```

This gives you:
- All 60+ NOVA organisms running
- Platform API + CLI for app deployments
- φ-weighted scheduling across sovereign nodes
- Full monitoring (Prometheus + Grafana)
- mTLS gateway for external access

---

*Casa de Medina — Sovereign Edge Cloud Platform*
