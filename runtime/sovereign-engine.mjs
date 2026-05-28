#!/usr/bin/env node
///
/// NOVA Multi-Runtime Sovereign Engine
///
/// Long-running service that hosts the NOVA runtime inside sovereign deployments.
/// Exposes HTTP health/status/metrics endpoints and runs the full multi-substrate
/// execution engine (heartbeat, protocol binder, Kuramoto synchronization).
///
/// Environment:
///   NOVA_RUNTIME_PORT        — HTTP port (default: 7700)
///   NOVA_HEARTBEAT_MS        — Heartbeat interval (default: 873)
///   NOVA_SUBSTRATES          — Comma-separated substrate list
///   NOVA_EMERGENCE_THRESHOLD — Emergence detection threshold (default: 0.89)
///   NOVA_KURAMOTO_COUPLING   — Phase coupling constant (default: 0.618)
///
/// Casa de Medina — Architectos de Architectura Inteligente
///

import { createServer } from 'node:http';

// ══════════════════════════════════════════════════════════════════
//  CONFIGURATION
// ══════════════════════════════════════════════════════════════════

const PORT = parseInt(process.env.NOVA_RUNTIME_PORT || '7700', 10);
const HEARTBEAT_MS = parseInt(process.env.NOVA_HEARTBEAT_MS || '873', 10);
const SUBSTRATES = (process.env.NOVA_SUBSTRATES || 'motoko,typescript,python,cpp,java,webworker').split(',');
const EMERGENCE_THRESHOLD = parseFloat(process.env.NOVA_EMERGENCE_THRESHOLD || '0.89');
const KURAMOTO_COUPLING = parseFloat(process.env.NOVA_KURAMOTO_COUPLING || '0.618');

const PHI = 1.6180339887498948482;
const PHI_PHASE_OFFSET = 2.39996322972865332;

// ══════════════════════════════════════════════════════════════════
//  RUNTIME ENGINE (self-contained, mirrors runtime/native-runtime.ts)
// ══════════════════════════════════════════════════════════════════

class SovereignRuntime {
  constructor() {
    this.organisms = new Map();
    this.cycleCount = 0;
    this.startTime = Date.now();
    this.heartbeatHandle = null;
    this.protocolBindings = new Map();
    this.executionCount = 0;
    this.lastEmergence = false;
  }

  register(id, name, substrate, generation) {
    const organism = {
      id, name, substrate, generation,
      miniHeart: { health: 100, pulse: 60, energy: 100, stress: 0, lastBeat: Date.now(), phiResonance: 1.0 },
      miniBrain: { synapseCount: 0, learningRate: PHI * 0.01, memoryCapacity: 1000, lastUpdate: Date.now() },
      phase: Math.random() * 2 * Math.PI,
      frequency: PHI,
      active: true,
      timestamp: Date.now(),
    };
    this.organisms.set(id, organism);
    return organism;
  }

  start() {
    this.heartbeatHandle = setInterval(() => this.heartbeat(), HEARTBEAT_MS);
  }

  stop() {
    if (this.heartbeatHandle) {
      clearInterval(this.heartbeatHandle);
      this.heartbeatHandle = null;
    }
  }

  heartbeat() {
    this.cycleCount++;
    const phiPhase = (this.cycleCount * PHI_PHASE_OFFSET) % (2 * Math.PI);
    for (const [, org] of this.organisms) {
      // Kuramoto synchronization
      const phaseDiff = phiPhase - org.phase;
      org.phase += org.frequency + KURAMOTO_COUPLING * Math.sin(phaseDiff);
      org.phase = org.phase % (2 * Math.PI);
      // Mini-heart update
      org.miniHeart.phiResonance = 0.5 + 0.5 * Math.cos(org.phase);
      org.miniHeart.energy = Math.max(10, org.miniHeart.energy - 0.01);
      org.miniHeart.health = org.miniHeart.energy * org.miniHeart.phiResonance;
      org.miniHeart.lastBeat = Date.now();
    }
    this.lastEmergence = this.checkEmergence();
  }

  checkEmergence() {
    if (this.organisms.size < 3) return false;
    let sumSin = 0, sumCos = 0;
    for (const org of this.organisms.values()) {
      sumSin += Math.sin(org.phase);
      sumCos += Math.cos(org.phase);
    }
    const N = this.organisms.size;
    const R = Math.sqrt(sumSin * sumSin + sumCos * sumCos) / N;
    return R > EMERGENCE_THRESHOLD;
  }

  bindProtocol(protocolId, targetOrganisms) {
    this.protocolBindings.set(protocolId, targetOrganisms);
  }

  executeProtocol(protocolId, substrate, input) {
    this.executionCount++;
    return { status: 'success', protocolId, substrate, cycle: this.cycleCount };
  }

  stats() {
    const activeCount = Array.from(this.organisms.values()).filter(o => o.active).length;
    let totalHealth = 0;
    for (const org of this.organisms.values()) totalHealth += org.miniHeart.health;
    const substrateDistribution = {};
    for (const org of this.organisms.values()) {
      substrateDistribution[org.substrate] = (substrateDistribution[org.substrate] || 0) + 1;
    }
    return {
      uptime_ms: Date.now() - this.startTime,
      cycle_count: this.cycleCount,
      heartbeat_ms: HEARTBEAT_MS,
      total_organisms: this.organisms.size,
      active_organisms: activeCount,
      avg_health: this.organisms.size > 0 ? (totalHealth / this.organisms.size).toFixed(2) : 0,
      emergence_detected: this.lastEmergence,
      protocol_bindings: this.protocolBindings.size,
      total_executions: this.executionCount,
      substrates: substrateDistribution,
    };
  }
}

// ══════════════════════════════════════════════════════════════════
//  BOOTSTRAP — Register all organisms and protocols
// ══════════════════════════════════════════════════════════════════

const rt = new SovereignRuntime();

// Register organisms across all configured substrates
const ORGANISM_CONFIGS = [
  // Core intelligence (Gen 0)
  { id: 'agi_main', name: 'AGI_MAIN', substrate: 'motoko', gen: 0 },
  { id: 'cordex', name: 'CORDEX', substrate: 'motoko', gen: 0 },
  { id: 'cerebex', name: 'CEREBEX', substrate: 'motoko', gen: 0 },
  { id: 'cyclovex', name: 'CYCLOVEX', substrate: 'motoko', gen: 0 },
  { id: 'spinor', name: 'SPINOR', substrate: 'motoko', gen: 0 },
  { id: 'vrt', name: 'VRT', substrate: 'motoko', gen: 0 },
  // Gen 1
  { id: 'chrysalis', name: 'CHRYSALIS', substrate: 'motoko', gen: 1 },
  { id: 'scribe', name: 'SCRIBE', substrate: 'motoko', gen: 1 },
  { id: 'architect', name: 'ARCHITECT', substrate: 'motoko', gen: 1 },
  { id: 'nexus', name: 'NEXUS', substrate: 'motoko', gen: 1 },
  { id: 'sovereign', name: 'SOVEREIGN', substrate: 'motoko', gen: 1 },
  { id: 'observer', name: 'OBSERVER', substrate: 'motoko', gen: 1 },
  // Infrastructure (Gen 1)
  { id: 'terminal', name: 'TERMINAL', substrate: 'motoko', gen: 1 },
  { id: 'custos', name: 'CUSTOS', substrate: 'motoko', gen: 1 },
  { id: 'praesidium', name: 'PRAESIDIUM', substrate: 'motoko', gen: 1 },
  { id: 'brain', name: 'BRAIN', substrate: 'motoko', gen: 1 },
  // Economic (Gen 2)
  { id: 'nova_token', name: 'NOVA_TOKEN', substrate: 'motoko', gen: 2 },
  { id: 'nns_proxy', name: 'NNS_PROXY', substrate: 'motoko', gen: 2 },
  { id: 'cycles_market', name: 'CYCLES_MARKET', substrate: 'motoko', gen: 2 },
  { id: 'parallax', name: 'PARALLAX', substrate: 'motoko', gen: 2 },
  { id: 'divi', name: 'DIVI', substrate: 'motoko', gen: 2 },
  { id: 'revenue_engine', name: 'REVENUE_ENGINE', substrate: 'motoko', gen: 2 },
  { id: 'sns_dao', name: 'SNS_DAO', substrate: 'motoko', gen: 2 },
  { id: 'auto_market', name: 'AUTO_MARKET', substrate: 'motoko', gen: 2 },
  // Advanced (Gen 3)
  { id: 'turing', name: 'TURING', substrate: 'motoko', gen: 3 },
  { id: 'braindex', name: 'BRAINDEX', substrate: 'motoko', gen: 3 },
  { id: 'chronex', name: 'CHRONEX', substrate: 'motoko', gen: 3 },
  { id: 'fluxton', name: 'FLUXTON', substrate: 'motoko', gen: 3 },
  { id: 'bronvox', name: 'BRONVOX', substrate: 'motoko', gen: 3 },
  { id: 'veritex', name: 'VERITEX', substrate: 'motoko', gen: 3 },
  { id: 'effecttrace', name: 'EFFECTTRACE', substrate: 'motoko', gen: 3 },
  { id: 'pulse', name: 'PULSE', substrate: 'motoko', gen: 3 },
  { id: 'pulse_scheduler', name: 'PULSE_SCHEDULER', substrate: 'motoko', gen: 3 },
  { id: 'synapse_field', name: 'SYNAPSE_FIELD', substrate: 'motoko', gen: 3 },
  // Protocol engine + Elements (Gen 4)
  { id: 'protocol_engine', name: 'PROTOCOL_ENGINE', substrate: 'motoko', gen: 4 },
  { id: 'aurum', name: 'AURUM', substrate: 'motoko', gen: 4 },
  { id: 'argentum', name: 'ARGENTUM', substrate: 'motoko', gen: 4 },
  { id: 'crimson', name: 'CRIMSON', substrate: 'motoko', gen: 4 },
  { id: 'ferrum', name: 'FERRUM', substrate: 'motoko', gen: 4 },
  { id: 'cuprum', name: 'CUPRUM', substrate: 'motoko', gen: 4 },
  { id: 'platinum', name: 'PLATINUM', substrate: 'motoko', gen: 4 },
  { id: 'silicon', name: 'SILICON', substrate: 'motoko', gen: 4 },
  { id: 'carbon', name: 'CARBON', substrate: 'motoko', gen: 4 },
  // Multi-substrate runtime organisms
  { id: 'rt_typescript', name: 'RUNTIME_TS', substrate: 'typescript', gen: 0 },
  { id: 'rt_python', name: 'RUNTIME_PY', substrate: 'python', gen: 0 },
  { id: 'rt_cpp', name: 'RUNTIME_CPP', substrate: 'cpp', gen: 0 },
  { id: 'rt_java', name: 'RUNTIME_JAVA', substrate: 'java', gen: 0 },
  { id: 'rt_webworker', name: 'RUNTIME_WW', substrate: 'webworker', gen: 0 },
];

for (const cfg of ORGANISM_CONFIGS) {
  if (SUBSTRATES.includes(cfg.substrate)) {
    rt.register(cfg.id, cfg.name, cfg.substrate, cfg.gen);
  }
}

// Bind all 275 protocols (200 base + 75 alpha)
for (let i = 1; i <= 200; i++) {
  rt.bindProtocol(`PROTO-${i}`, ['agi_main', 'protocol_engine', 'nexus']);
}
for (let i = 201; i <= 275; i++) {
  rt.bindProtocol(`PROTO-${i}`, ['agi_main', 'architect', 'sovereign']);
}

// Start the heartbeat
rt.start();
console.log(`[NOVA] Multi-Runtime Sovereign Engine started`);
console.log(`[NOVA]   Substrates: ${SUBSTRATES.join(', ')}`);
console.log(`[NOVA]   Organisms:  ${rt.organisms.size}`);
console.log(`[NOVA]   Protocols:  ${rt.protocolBindings.size}`);
console.log(`[NOVA]   Heartbeat:  ${HEARTBEAT_MS}ms (φ-derived)`);
console.log(`[NOVA]   Port:       ${PORT}`);

// ══════════════════════════════════════════════════════════════════
//  HTTP SERVICE — Health, Status, Metrics, Protocol Execution
// ══════════════════════════════════════════════════════════════════

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === '/health') {
    const stats = rt.stats();
    const healthy = stats.active_organisms > 0 && stats.cycle_count > 0;
    res.writeHead(healthy ? 200 : 503, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: healthy ? 'healthy' : 'degraded', ...stats }));
    return;
  }

  if (url.pathname === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(rt.stats()));
    return;
  }

  if (url.pathname === '/metrics') {
    const stats = rt.stats();
    const metrics = [
      '# HELP nova_runtime_uptime_seconds NOVA runtime uptime',
      '# TYPE nova_runtime_uptime_seconds gauge',
      `nova_runtime_uptime_seconds ${(stats.uptime_ms / 1000).toFixed(1)}`,
      '# HELP nova_runtime_cycles Total heartbeat cycles',
      '# TYPE nova_runtime_cycles counter',
      `nova_runtime_cycles ${stats.cycle_count}`,
      '# HELP nova_organisms_total Total registered organisms',
      '# TYPE nova_organisms_total gauge',
      `nova_organisms_total ${stats.total_organisms}`,
      '# HELP nova_organisms_active Active organisms',
      '# TYPE nova_organisms_active gauge',
      `nova_organisms_active ${stats.active_organisms}`,
      '# HELP nova_organisms_avg_health Average organism health',
      '# TYPE nova_organisms_avg_health gauge',
      `nova_organisms_avg_health ${stats.avg_health}`,
      '# HELP nova_emergence_detected Whether emergence is detected',
      '# TYPE nova_emergence_detected gauge',
      `nova_emergence_detected ${stats.emergence_detected ? 1 : 0}`,
      '# HELP nova_protocol_bindings Total protocol bindings',
      '# TYPE nova_protocol_bindings gauge',
      `nova_protocol_bindings ${stats.protocol_bindings}`,
      '# HELP nova_protocol_executions Total protocol executions',
      '# TYPE nova_protocol_executions counter',
      `nova_protocol_executions ${stats.total_executions}`,
    ];
    // Per-substrate organism count
    for (const [sub, count] of Object.entries(stats.substrates)) {
      metrics.push(`nova_substrate_organisms{substrate="${sub}"} ${count}`);
    }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(metrics.join('\n') + '\n');
    return;
  }

  if (url.pathname === '/execute' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { protocolId, substrate, input } = JSON.parse(body);
        const result = rt.executeProtocol(protocolId || 'PROTO-201', substrate || 'typescript', input || {});
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // Default: info page
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    service: 'NOVA Multi-Runtime Sovereign Engine',
    version: '1.0.0',
    endpoints: ['/health', '/status', '/metrics', '/execute'],
    substrates: SUBSTRATES,
    heartbeat_ms: HEARTBEAT_MS,
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[NOVA] HTTP service listening on :${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[NOVA] SIGTERM received — shutting down...');
  rt.stop();
  server.close(() => process.exit(0));
});
process.on('SIGINT', () => {
  rt.stop();
  server.close(() => process.exit(0));
});
