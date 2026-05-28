# 🚀 NOVA DEPLOY — Native Sovereign Deployment

**Like Fly.io gives you a URL — NOVA Deploy gives you a URL. But it's YOURS.**

---

## Quick Start

```bash
# See all options
./scripts/nova deploy

# Deploy to ICP (fastest path to a LIVE permanent URL)
./scripts/nova deploy icp

# Deploy to Cloudflare (if you have a paid account)
./scripts/nova deploy cloudflare

# Deploy sovereign Docker node (full self-hosted stack)
./scripts/nova deploy sovereign

# Deploy everywhere at once
./scripts/nova deploy all

# Check your live URLs
./scripts/nova deploy status
```

---

## Deployment Targets

### 1. 🌐 Internet Computer (ICP) — `deploy icp`

**What you get:** `https://<canister-id>.ic0.app`

This is the NATIVE path. Your dashboard runs ON the blockchain. Permanent. Decentralized. Unstoppable. No server. No host. No monthly bill.

**Prerequisites:**
```bash
# Install dfx (Internet Computer SDK)
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"

# Create identity (first time only)
dfx identity new nova-deployer
dfx identity use nova-deployer

# Get cycles (needed for mainnet deployment)
# Option A: Free faucet (limited)
# https://faucet.dfinity.org
# Option B: Buy ICP → convert to cycles
```

**Deploy:**
```bash
./scripts/nova deploy icp
# or
npm run deploy:icp
```

**Result:**
```
✓ Dashboard → https://abc12-def34-xyz.ic0.app
✓ Permanent. Decentralized. Runs on 1000+ nodes worldwide.
```

---

### 2. ☁️ Cloudflare Pages — `deploy cloudflare`

**What you get:** `https://nova-protocol.pages.dev`

Edge network deployment. 300+ cities. <50ms globally. Uses YOUR paid Cloudflare account.

**Prerequisites:**
```bash
npm install -g wrangler
wrangler login
```

**Deploy:**
```bash
./scripts/nova deploy cloudflare
# or
npm run deploy:cloudflare
```

**Custom Domain:**
1. Cloudflare Dashboard → Pages → nova-protocol → Custom domains
2. Add `nova.yourdomain.com`
3. SSL handled automatically

---

### 3. 🏛️ Sovereign Node (Docker) — `deploy sovereign`

**What you get:** Full NOVA stack running on YOUR infrastructure with YOUR domain.

The complete sovereign deployment: IC replica, 60+ canisters, cognitive engines, TypeScript SDK, admin dashboard — all in one Docker container.

**Prerequisites:**
```bash
# Docker installed
docker --version
```

**Deploy:**
```bash
./scripts/nova deploy sovereign
# or
npm run deploy:sovereign
```

**Then run it:**
```bash
docker run -d \
  -p 3000:3000 \
  -p 8080:8080 \
  -p 7700:7700 \
  --name nova \
  nova-sovereign:latest
```

**For production with a public URL:**
1. Push to any container registry
2. Deploy on any cloud VM (AWS, GCP, Azure, Hetzner, DigitalOcean, etc.)
3. Point DNS A record to VM IP
4. Done → `https://your-domain.com`

---

### 4. 📱 PWA Bundle — `deploy pwa`

**What you get:** An installable, offline-capable progressive web app.

The PWA works on any device — phone, tablet, desktop. Users can install it to their home screen. Works offline. Full sovereignty.

```bash
./scripts/nova deploy pwa
# or
npm run deploy:pwa
```

The PWA bundle at `.nova/pwa-deploy/` can then be deployed to ANY target:
- Upload to ICP (permanent)
- Upload to Cloudflare (fast)
- Upload to your own server
- Distribute as a zip

---

## All Commands

| Command | What it does |
|---------|--------------|
| `./scripts/nova deploy` | Show all targets |
| `./scripts/nova deploy icp` | Deploy to Internet Computer (get blockchain URL) |
| `./scripts/nova deploy cloudflare` | Deploy to Cloudflare Pages |
| `./scripts/nova deploy sovereign` | Build sovereign Docker container |
| `./scripts/nova deploy pwa` | Bundle as installable PWA |
| `./scripts/nova deploy all` | Deploy to ALL targets |
| `./scripts/nova deploy status` | Show all live URLs |
| `./scripts/nova deploy <canister>` | Deploy individual canister to ICP |

---

## npm Scripts (Shorthand)

```bash
npm run deploy              # interactive
npm run deploy:icp          # → blockchain URL
npm run deploy:cloudflare   # → pages.dev URL
npm run deploy:sovereign    # → docker image
npm run deploy:pwa          # → PWA bundle
npm run deploy:all          # → everything
npm run deploy:status       # → show URLs
```

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│           NOVA DEPLOY ENGINE                     │
│         scripts/nova-deploy.mjs                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌─────────┐  ┌───────────┐  ┌──────────────┐  │
│  │   ICP   │  │Cloudflare │  │  Sovereign   │  │
│  │ dfx SDK │  │ wrangler  │  │   Docker     │  │
│  └────┬────┘  └─────┬─────┘  └──────┬───────┘  │
│       │              │               │           │
│       ▼              ▼               ▼           │
│  .ic0.app      .pages.dev      your-domain      │
│  (blockchain)  (edge CDN)      (sovereign)       │
│                                                  │
└─────────────────────────────────────────────────┘
```

**This is NOT a wrapper around someone else's platform.** This is YOUR deployment engine that uses the available infrastructure to give you URLs — just like Fly.io, but sovereign.

---

## Frontend Asset Canister

The `nova_frontend` canister in `dfx.json` serves your dashboard directly from the Internet Computer:

```json
{
  "nova_frontend": {
    "type": "assets",
    "source": ["public", "dist/pwa"]
  }
}
```

When deployed to ICP, the canister IS your web server. No nginx. No CDN. No hosting bill. The blockchain serves your HTML/JS/CSS directly.
