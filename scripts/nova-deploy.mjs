#!/usr/bin/env node
/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * NOVA DEPLOY — Native Sovereign Deployment Engine
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * Like Fly.io gives you a URL — NOVA Deploy gives you a URL.
 * But it's YOUR infrastructure. YOUR protocol. YOUR sovereignty.
 *
 * Targets:
 *   icp       → Deploy to Internet Computer → get https://<canister-id>.ic0.app
 *   pwa       → Deploy PWA bundle → get https://<name>.nova.host (sovereign)
 *   cloudflare → Deploy to Cloudflare Pages → get https://<name>.pages.dev
 *   sovereign → Deploy Docker sovereign node → get https://<your-domain>
 *   all       → Deploy everywhere simultaneously
 *
 * Usage:
 *   nova-deploy                    (interactive — pick target)
 *   nova-deploy icp                (deploy canisters + frontend to IC)
 *   nova-deploy pwa                (deploy PWA to sovereign hosting)
 *   nova-deploy cloudflare         (deploy to Cloudflare Pages)
 *   nova-deploy sovereign          (deploy full Docker sovereign node)
 *   nova-deploy all                (deploy to all targets)
 *   nova-deploy status             (show live URLs for all deployments)
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 */

import { execSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, cpSync } from 'node:fs';
import { resolve, join } from 'node:path';

// ── Constants ────────────────────────────────────────────────────────────────
const ROOT = resolve(import.meta.dirname || process.cwd(), '..');
const DEPLOY_STATE = join(ROOT, '.nova', 'deploy-state.json');
const PUBLIC_DIR = join(ROOT, 'public');
const PWA_DIR = join(ROOT, 'dist', 'pwa');

const PHI = 1.6180339887;
const VERSION = '1.0.0';

// ── ANSI Colors ──────────────────────────────────────────────────────────────
const C = {
  gold: '\x1b[33m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
  reset: '\x1b[0m',
};

const log = (msg) => console.log(`${C.gold}▸${C.reset} ${msg}`);
const logOk = (msg) => console.log(`${C.green}✓${C.reset} ${msg}`);
const logErr = (msg) => console.error(`${C.red}✗${C.reset} ${msg}`);
const logUrl = (label, url) => console.log(`  ${C.cyan}${label}${C.reset} → ${C.bold}${url}${C.reset}`);

// ── State Management ─────────────────────────────────────────────────────────
function loadState() {
  if (existsSync(DEPLOY_STATE)) {
    return JSON.parse(readFileSync(DEPLOY_STATE, 'utf-8'));
  }
  return { deployments: {}, lastDeploy: null };
}

function saveState(state) {
  mkdirSync(join(ROOT, '.nova'), { recursive: true });
  writeFileSync(DEPLOY_STATE, JSON.stringify(state, null, 2));
}

// ── Shell execution helper ───────────────────────────────────────────────────
function run(cmd, opts = {}) {
  try {
    return execSync(cmd, {
      cwd: opts.cwd || ROOT,
      encoding: 'utf-8',
      stdio: opts.silent ? 'pipe' : 'inherit',
      ...opts,
    });
  } catch (e) {
    if (opts.allowFail) return e.stdout || '';
    throw e;
  }
}

function runSilent(cmd) {
  return run(cmd, { silent: true, allowFail: true });
}

// ── Check prerequisites ──────────────────────────────────────────────────────
function checkTool(name) {
  try {
    execSync(`command -v ${name}`, { stdio: 'pipe' });
    return true;
  } catch { return false; }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TARGET: ICP (Internet Computer)
// Deploy → get https://<canister-id>.ic0.app URL
// ═══════════════════════════════════════════════════════════════════════════════
async function deployICP() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOY → Internet Computer ═══${C.reset}\n`);

  if (!checkTool('dfx')) {
    logErr('dfx not installed. Install: sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"');
    process.exit(1);
  }

  // Check identity
  log('Checking ICP identity...');
  const identity = runSilent('dfx identity whoami').trim();
  logOk(`Identity: ${identity}`);

  // Check cycles balance
  log('Checking cycles wallet...');
  const balance = runSilent('dfx wallet --network ic balance 2>/dev/null').trim();
  if (balance) {
    logOk(`Wallet balance: ${balance}`);
  } else {
    log('No cycles wallet configured (needed for mainnet deploy)');
    log('Get cycles: https://faucet.dfinity.org or buy ICP → convert');
  }

  // Build the frontend asset canister
  log('Building frontend assets for ICP...');
  const icpAssetsDir = join(ROOT, '.nova', 'icp-assets');
  mkdirSync(icpAssetsDir, { recursive: true });

  // Copy PWA assets into ICP asset directory
  if (existsSync(PWA_DIR)) {
    cpSync(PWA_DIR, icpAssetsDir, { recursive: true });
  } else if (existsSync(PUBLIC_DIR)) {
    cpSync(PUBLIC_DIR, icpAssetsDir, { recursive: true });
  } else {
    cpSync(join(ROOT, 'index.html'), join(icpAssetsDir, 'index.html'));
    if (existsSync(join(ROOT, 'founder-dashboard.html'))) {
      cpSync(join(ROOT, 'founder-dashboard.html'), join(icpAssetsDir, 'founder-dashboard.html'));
    }
  }

  logOk('Frontend assets prepared');

  // Create temporary dfx.json for frontend canister if not exists
  const dfxConfig = JSON.parse(readFileSync(join(ROOT, 'dfx.json'), 'utf-8'));
  if (!dfxConfig.canisters.nova_frontend) {
    dfxConfig.canisters.nova_frontend = {
      type: 'assets',
      source: ['.nova/icp-assets'],
    };
    writeFileSync(join(ROOT, 'dfx.json'), JSON.stringify(dfxConfig, null, 2));
    logOk('Added nova_frontend asset canister to dfx.json');
  }

  // Deploy to IC mainnet
  log('Deploying to Internet Computer mainnet...');
  console.log(`${C.dim}  This creates a canister and gives you a permanent URL${C.reset}\n`);

  try {
    run('dfx deploy nova_frontend --network ic');
  } catch (e) {
    logErr('Mainnet deploy failed. Trying local replica for preview...');
    log('Starting local replica...');
    run('dfx start --background --clean', { allowFail: true });
    run('dfx deploy nova_frontend');
    const localId = runSilent('dfx canister id nova_frontend').trim();
    logOk('Deployed to LOCAL replica');
    logUrl('Local Dashboard', `http://localhost:4943/?canisterId=${localId}`);
    logUrl('Local Alt URL', `http://${localId}.localhost:4943`);

    const state = loadState();
    state.deployments.icp_local = {
      url: `http://${localId}.localhost:4943`,
      canisterId: localId,
      timestamp: new Date().toISOString(),
      network: 'local',
    };
    state.lastDeploy = 'icp_local';
    saveState(state);
    return;
  }

  // Get the canister ID → that's the URL
  const canisterId = runSilent('dfx canister --network ic id nova_frontend').trim();
  const icUrl = `https://${canisterId}.ic0.app`;
  const rawUrl = `https://${canisterId}.raw.ic0.app`;

  console.log(`\n${C.bold}${C.green}═══ DEPLOYED TO ICP ═══${C.reset}\n`);
  logUrl('Dashboard', icUrl);
  logUrl('Raw URL', rawUrl);
  logUrl('Canister ID', canisterId);
  console.log(`\n${C.dim}  This URL is permanent, decentralized, and unstoppable.${C.reset}`);
  console.log(`${C.dim}  No server. No host. It runs on the Internet Computer blockchain.${C.reset}\n`);

  const state = loadState();
  state.deployments.icp = {
    url: icUrl,
    rawUrl,
    canisterId,
    timestamp: new Date().toISOString(),
    network: 'ic',
  };
  state.lastDeploy = 'icp';
  saveState(state);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TARGET: PWA (Progressive Web App — Sovereign Hosting)
// Deploy as installable app that runs from YOUR domain
// ═══════════════════════════════════════════════════════════════════════════════
async function deployPWA() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOY → PWA (Sovereign) ═══${C.reset}\n`);

  // Build the PWA bundle
  log('Building PWA bundle...');
  const pwaOutDir = join(ROOT, '.nova', 'pwa-deploy');
  mkdirSync(pwaOutDir, { recursive: true });

  // Gather all PWA assets
  if (existsSync(PWA_DIR)) {
    cpSync(PWA_DIR, pwaOutDir, { recursive: true });
    logOk('PWA bundle assembled from dist/pwa');
  } else {
    // Assemble from root
    cpSync(join(ROOT, 'index.html'), join(pwaOutDir, 'index.html'));
    if (existsSync(join(ROOT, 'founder-dashboard.html'))) {
      cpSync(join(ROOT, 'founder-dashboard.html'), join(pwaOutDir, 'founder-dashboard.html'));
    }
    if (existsSync(PUBLIC_DIR)) {
      cpSync(PUBLIC_DIR, pwaOutDir, { recursive: true });
    }
    logOk('PWA bundle assembled from project root');
  }

  // Generate deployment manifest
  const manifest = {
    name: 'nova-protocol',
    version: VERSION,
    type: 'pwa',
    assets: pwaOutDir,
    timestamp: new Date().toISOString(),
    phi_signature: (Math.random() * PHI).toFixed(8),
  };
  writeFileSync(join(pwaOutDir, 'nova-deploy.json'), JSON.stringify(manifest, null, 2));

  console.log(`\n${C.bold}${C.green}═══ PWA BUNDLE READY ═══${C.reset}\n`);
  log('PWA bundle location: .nova/pwa-deploy/');
  console.log('');
  log('Deploy options:');
  console.log('');
  logUrl('Option 1 — ICP', 'Run: nova-deploy icp  (permanent blockchain URL)');
  logUrl('Option 2 — Cloudflare', 'Run: nova-deploy cloudflare  (pages.dev URL)');
  logUrl('Option 3 — Docker', 'Run: nova-deploy sovereign  (your own server)');
  logUrl('Option 4 — Any static host', `Upload .nova/pwa-deploy/ to any web server`);
  console.log('');
  log('The PWA is installable — users can add it to their home screen.');
  log('Works offline via service worker. Full sovereign operation.');

  const state = loadState();
  state.deployments.pwa = {
    bundlePath: pwaOutDir,
    timestamp: new Date().toISOString(),
    status: 'bundled',
  };
  saveState(state);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TARGET: Cloudflare Pages
// Deploy → get https://<name>.pages.dev URL
// ═══════════════════════════════════════════════════════════════════════════════
async function deployCloudflare() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOY → Cloudflare Pages ═══${C.reset}\n`);

  if (!checkTool('npx')) {
    logErr('Node.js/npx not installed');
    process.exit(1);
  }

  // Ensure public/ is ready
  if (!existsSync(join(PUBLIC_DIR, 'index.html'))) {
    log('Building public/ directory...');
    mkdirSync(PUBLIC_DIR, { recursive: true });
    cpSync(join(ROOT, 'index.html'), join(PUBLIC_DIR, 'index.html'));
    if (existsSync(join(ROOT, 'founder-dashboard.html'))) {
      cpSync(join(ROOT, 'founder-dashboard.html'), join(PUBLIC_DIR, 'founder-dashboard.html'));
    }
  }

  // Check wrangler auth
  log('Checking Cloudflare authentication...');
  const whoami = runSilent('npx wrangler whoami 2>&1');
  if (whoami.includes('not authenticated') || whoami.includes('error')) {
    logErr('Not logged into Cloudflare. Run: npx wrangler login');
    process.exit(1);
  }
  logOk('Cloudflare authenticated');

  // Deploy
  log('Deploying to Cloudflare Pages...');
  run('npx wrangler pages deploy public --project-name=nova-protocol');

  const cfUrl = 'https://nova-protocol.pages.dev';
  console.log(`\n${C.bold}${C.green}═══ DEPLOYED TO CLOUDFLARE ═══${C.reset}\n`);
  logUrl('Dashboard', cfUrl);
  logUrl('Founder', `${cfUrl}/founder-dashboard.html`);
  console.log(`\n${C.dim}  Cloudflare edge network — 300+ cities, <50ms globally${C.reset}\n`);

  const state = loadState();
  state.deployments.cloudflare = {
    url: cfUrl,
    timestamp: new Date().toISOString(),
    projectName: 'nova-protocol',
  };
  state.lastDeploy = 'cloudflare';
  saveState(state);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TARGET: Sovereign Node (Docker)
// Deploy full sovereign stack → get URL on YOUR infrastructure
// ═══════════════════════════════════════════════════════════════════════════════
async function deploySovereign() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOY → Sovereign Node ═══${C.reset}\n`);

  if (!checkTool('docker')) {
    logErr('Docker not installed. Install: https://docs.docker.com/get-docker/');
    process.exit(1);
  }

  const dockerDir = join(ROOT, 'deploy', 'docker');
  if (!existsSync(join(dockerDir, 'Dockerfile'))) {
    logErr('Dockerfile not found at deploy/docker/Dockerfile');
    process.exit(1);
  }

  log('Building sovereign node container...');
  run(`docker build -t nova-sovereign:latest -f ${dockerDir}/Dockerfile .`);
  logOk('Container built: nova-sovereign:latest');

  console.log(`\n${C.bold}${C.green}═══ SOVEREIGN NODE READY ═══${C.reset}\n`);
  log('Run locally:');
  console.log(`  ${C.cyan}docker run -d -p 3000:3000 -p 8080:8080 -p 7700:7700 nova-sovereign:latest${C.reset}`);
  console.log('');
  log('Then access:');
  logUrl('Dashboard', 'http://localhost:3000');
  logUrl('Canister API', 'http://localhost:8080');
  logUrl('NOVA Runtime', 'http://localhost:7700');
  console.log('');
  log('For production with a public URL:');
  console.log(`  ${C.dim}1. Push to your container registry:${C.reset}`);
  console.log(`     docker tag nova-sovereign:latest your-registry.com/nova-sovereign`);
  console.log(`     docker push your-registry.com/nova-sovereign`);
  console.log(`  ${C.dim}2. Deploy on any cloud VM (has Docker):${C.reset}`);
  console.log(`     docker run -d -p 443:3000 --name nova nova-sovereign:latest`);
  console.log(`  ${C.dim}3. Point your domain's DNS A record to the VM's IP${C.reset}`);
  console.log(`  ${C.dim}4. Done — https://your-domain.com is your NOVA sovereign node${C.reset}`);
  console.log('');

  const state = loadState();
  state.deployments.sovereign = {
    image: 'nova-sovereign:latest',
    timestamp: new Date().toISOString(),
    status: 'built',
  };
  state.lastDeploy = 'sovereign';
  saveState(state);
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATUS — Show all active deployment URLs
// ═══════════════════════════════════════════════════════════════════════════════
function showStatus() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOYMENT STATUS ═══${C.reset}\n`);

  const state = loadState();
  const d = state.deployments;

  if (Object.keys(d).length === 0) {
    log('No deployments yet. Run: nova-deploy <target>');
    console.log('');
    log('Available targets:');
    console.log(`  ${C.cyan}icp${C.reset}         → Internet Computer (blockchain URL, permanent)`);
    console.log(`  ${C.cyan}pwa${C.reset}         → Progressive Web App bundle`);
    console.log(`  ${C.cyan}cloudflare${C.reset}  → Cloudflare Pages (edge network)`);
    console.log(`  ${C.cyan}sovereign${C.reset}   → Docker sovereign node (your server)`);
    console.log(`  ${C.cyan}all${C.reset}         → Deploy to ALL targets`);
    return;
  }

  if (d.icp) {
    logUrl('ICP (Blockchain)', d.icp.url);
    console.log(`    ${C.dim}Canister: ${d.icp.canisterId} | Deployed: ${d.icp.timestamp}${C.reset}`);
  }
  if (d.icp_local) {
    logUrl('ICP (Local)', d.icp_local.url);
    console.log(`    ${C.dim}Canister: ${d.icp_local.canisterId} | Local replica${C.reset}`);
  }
  if (d.cloudflare) {
    logUrl('Cloudflare', d.cloudflare.url);
    console.log(`    ${C.dim}Project: ${d.cloudflare.projectName} | Deployed: ${d.cloudflare.timestamp}${C.reset}`);
  }
  if (d.pwa) {
    logUrl('PWA Bundle', d.pwa.bundlePath);
    console.log(`    ${C.dim}Status: ${d.pwa.status} | Built: ${d.pwa.timestamp}${C.reset}`);
  }
  if (d.sovereign) {
    logUrl('Sovereign Node', `docker: ${d.sovereign.image}`);
    console.log(`    ${C.dim}Status: ${d.sovereign.status} | Built: ${d.sovereign.timestamp}${C.reset}`);
  }

  console.log('');
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEPLOY ALL
// ═══════════════════════════════════════════════════════════════════════════════
async function deployAll() {
  console.log(`\n${C.bold}${C.gold}═══ NOVA DEPLOY → ALL TARGETS ═══${C.reset}\n`);
  log('Deploying to all available targets...\n');

  await deployPWA();
  await deployICP();
  await deployCloudflare();
  await deploySovereign();

  console.log(`\n${C.bold}${C.green}═══ ALL DEPLOYMENTS COMPLETE ═══${C.reset}\n`);
  showStatus();
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════
const target = process.argv[2] || '';

console.log(`${C.gold}${C.bold}`);
console.log(`  ╔═══════════════════════════════════════════════╗`);
console.log(`  ║  NOVA DEPLOY — Sovereign Deployment Engine    ║`);
console.log(`  ║  Like Fly.io gives URLs — but it's YOURS     ║`);
console.log(`  ╚═══════════════════════════════════════════════╝`);
console.log(`${C.reset}`);

switch (target) {
  case 'icp':
  case 'ic':
    await deployICP();
    break;
  case 'pwa':
    await deployPWA();
    break;
  case 'cloudflare':
  case 'cf':
    await deployCloudflare();
    break;
  case 'sovereign':
  case 'docker':
  case 'node':
    await deploySovereign();
    break;
  case 'all':
    await deployAll();
    break;
  case 'status':
  case 'urls':
    showStatus();
    break;
  default:
    console.log(`${C.bold}Usage:${C.reset}  nova-deploy <target>\n`);
    console.log(`${C.bold}Targets:${C.reset}`);
    console.log(`  ${C.cyan}icp${C.reset}         Deploy to Internet Computer blockchain`);
    console.log(`              → Get: https://<canister-id>.ic0.app (permanent, decentralized)`);
    console.log(`  ${C.cyan}pwa${C.reset}         Build sovereign PWA bundle`);
    console.log(`              → Installable offline-capable progressive web app`);
    console.log(`  ${C.cyan}cloudflare${C.reset}  Deploy to Cloudflare Pages`);
    console.log(`              → Get: https://nova-protocol.pages.dev (edge network)`);
    console.log(`  ${C.cyan}sovereign${C.reset}   Build Docker sovereign node`);
    console.log(`              → Get: https://your-domain.com (your own infrastructure)`);
    console.log(`  ${C.cyan}all${C.reset}         Deploy to ALL targets simultaneously`);
    console.log(`  ${C.cyan}status${C.reset}      Show URLs for all active deployments`);
    console.log('');
    console.log(`${C.bold}Quick start:${C.reset}`);
    console.log(`  ${C.green}nova-deploy icp${C.reset}         ← fastest path to a live URL`);
    console.log(`  ${C.green}nova-deploy cloudflare${C.reset}  ← if you have Cloudflare account`);
    console.log(`  ${C.green}nova-deploy sovereign${C.reset}   ← full self-hosted stack`);
    console.log('');
    break;
}
