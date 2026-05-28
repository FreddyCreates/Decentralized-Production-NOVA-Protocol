///
/// NOVA INFRA WORKER — 24/7 Infrastructure Orchestration
///
/// A permanent Web Worker for health monitoring of 13 subsystems,
/// Fibonacci-stepped auto-scaling (LAW-CO-034), blue-green canary
/// deploys with φ-weighted traffic splits, and φ-exponential
/// failover recovery (LAW-CM-038). 873ms heartbeat. Zero dependencies.
///

// ═══════════════════════════════════════════════════════════════
//  GOLDEN CONSTANTS
// ═══════════════════════════════════════════════════════════════

const PHI           = 1.6180339887498948482;
const PHI_INVERSE   = 0.6180339887498948482;
const GOLDEN_ANGLE  = 2.39996322972865332;
const HEARTBEAT_MS  = 873;

const FIB = [1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765];

function fibonacciHash(n, mod) {
  let h = n;
  for (let i = 0; i < 5; i++) {
    h = ((h * FIB[(n + i) % 20]) ^ (FIB[(h + i) % 20] * 2654435761)) >>> 0;
    h = (h + FIB[(i * 3 + 7) % 20]) >>> 0;
  }
  return h % mod;
}

var UNSAFE_KEYS = { '__proto__': 1, 'constructor': 1, 'prototype': 1 };

function safeKey(k) {
  return typeof k === 'string' && !UNSAFE_KEYS[k];
}

// ═══════════════════════════════════════════════════════════════
//  SUBSYSTEMS — 13 monitored infrastructure components
// ═══════════════════════════════════════════════════════════════

var SYSTEM_NAMES = [
  'engine-core','agent-fleet','memory-bank','protocol-stack',
  'safety-guard','render-pipeline','routing-table','crypto-vault',
  'contract-layer','telemetry-hub','extension-runtime','marketplace',
  'scheduler'
];

var SYSTEMS = {};

for (var si = 0; si < SYSTEM_NAMES.length; si++) {
  SYSTEMS[SYSTEM_NAMES[si]] = {
    name:        SYSTEM_NAMES[si],
    status:      'healthy',
    lastCheck:   0,
    latencyMs:   0,
    uptimeRatio: 1.0,
    checks:      0,
    anomalies:   0,
  };
}

var totalChecks   = 0;
var totalScales   = 0;
var totalDeploys  = 0;
var totalRecovers = 0;

// ═══════════════════════════════════════════════════════════════
//  NEAREST FIBONACCI
// ═══════════════════════════════════════════════════════════════

function nearestFib(n) {
  var best = FIB[0];
  for (var i = 1; i < FIB.length; i++) {
    if (Math.abs(FIB[i] - n) < Math.abs(best - n)) best = FIB[i];
  }
  return best;
}

// ═══════════════════════════════════════════════════════════════
//  HEALTH CHECK — simulate check with φ-tiered status
// ═══════════════════════════════════════════════════════════════

function healthCheck(systemName) {
  totalChecks++;
  if (!safeKey(systemName)) return { error: 'invalid system name' };
  var sys = SYSTEMS[systemName];
  if (!sys) return { error: 'system not found: ' + systemName };

  sys.checks++;
  sys.lastCheck = Date.now();

  var tierFactor = 1.0 + (SYSTEM_NAMES.indexOf(systemName) % 5) * 0.1;
  var hashBasis  = fibonacciHash(Date.now() + sys.checks, 1000);
  var latency    = (hashBasis / 1000) * PHI * tierFactor * 100;
  sys.latencyMs  = Math.round(latency * 100) / 100;

  var healthyThreshold  = PHI * 100;
  var degradedThreshold = PHI * PHI * 100;

  if (latency < healthyThreshold) {
    sys.status = 'healthy';
  } else if (latency < degradedThreshold) {
    sys.status = 'degraded';
    sys.anomalies++;
  } else {
    sys.status = 'critical';
    sys.anomalies++;
  }

  sys.uptimeRatio = sys.checks > 0
    ? (sys.checks - sys.anomalies) / sys.checks
    : 1.0;

  return {
    system:      systemName,
    status:      sys.status,
    latencyMs:   sys.latencyMs,
    uptimeRatio: Math.round(sys.uptimeRatio * 10000) / 10000,
    checks:      sys.checks,
    anomalies:   sys.anomalies,
  };
}

// ═══════════════════════════════════════════════════════════════
//  CHECK ALL — sweep all 13 subsystems
// ═══════════════════════════════════════════════════════════════

function checkAll() {
  var results = [];
  var healthy = 0, degraded = 0, critical = 0;

  for (var i = 0; i < SYSTEM_NAMES.length; i++) {
    var r = healthCheck(SYSTEM_NAMES[i]);
    results.push(r);
    if (r.status === 'healthy')  healthy++;
    if (r.status === 'degraded') degraded++;
    if (r.status === 'critical') critical++;
  }

  return {
    systems:  results,
    summary:  { healthy: healthy, degraded: degraded, critical: critical, total: SYSTEM_NAMES.length },
  };
}

// ═══════════════════════════════════════════════════════════════
//  AUTO-SCALE — Fibonacci-stepped scaling (LAW-CO-034)
// ═══════════════════════════════════════════════════════════════

function autoScale(systemName, load, capacity) {
  totalScales++;
  var ratio      = capacity > 0 ? load / capacity : 0;
  var scaleUp    = PHI_INVERSE;
  var scaleDown  = 1.0 / (PHI * PHI);
  var action     = 'none';
  var newCapacity = capacity;

  if (ratio > scaleUp) {
    var step     = nearestFib(Math.ceil(capacity * 0.2));
    newCapacity  = capacity + step;
    action       = 'scale-up';
  } else if (ratio < scaleDown) {
    var stepDown = nearestFib(Math.ceil(capacity * 0.1));
    newCapacity  = Math.max(1, capacity - stepDown);
    action       = 'scale-down';
  }

  return {
    system:      systemName,
    load:        load,
    oldCapacity: capacity,
    newCapacity: newCapacity,
    ratio:       Math.round(ratio * 10000) / 10000,
    action:      action,
    fibStep:     action !== 'none' ? nearestFib(Math.ceil(capacity * 0.15)) : 0,
    law:         'LAW-CO-034',
  };
}

// ═══════════════════════════════════════════════════════════════
//  CANARY DEPLOY — blue-green with φ-weighted traffic
// ═══════════════════════════════════════════════════════════════

function deployCanary(artifact, weight) {
  totalDeploys++;
  var trafficWeight = typeof weight === 'number' ? weight : PHI_INVERSE;

  return {
    artifact:       artifact || 'unknown',
    strategy:       'blue-green-canary',
    newTraffic:     Math.round(trafficWeight * 10000) / 10000,
    oldTraffic:     Math.round((1 - trafficWeight) * 10000) / 10000,
    phiSplit:       true,
    deployId:       fibonacciHash(Date.now(), 2147483647),
    timestamp:      Date.now(),
  };
}

// ═══════════════════════════════════════════════════════════════
//  RECOVER — φ-exponential backoff (LAW-CM-038)
// ═══════════════════════════════════════════════════════════════

var recoveryAttempts = {};

function recoverSystem(systemName) {
  totalRecovers++;
  if (!safeKey(systemName)) return { error: 'invalid system name' };
  var sys = SYSTEMS[systemName];
  if (!sys) return { error: 'system not found: ' + systemName };

  if (!recoveryAttempts[systemName]) recoveryAttempts[systemName] = 0;
  recoveryAttempts[systemName]++;

  var attempt = recoveryAttempts[systemName];
  var delay   = Math.pow(PHI, attempt) * 100;

  sys.status    = 'healthy';
  sys.anomalies = Math.max(0, sys.anomalies - 1);
  sys.uptimeRatio = sys.checks > 0
    ? (sys.checks - sys.anomalies) / sys.checks
    : 1.0;

  return {
    system:       systemName,
    attempt:      attempt,
    backoffMs:    Math.round(delay * 100) / 100,
    recovered:    true,
    newStatus:    sys.status,
    law:          'LAW-CM-038',
  };
}

// ═══════════════════════════════════════════════════════════════
//  HEARTBEAT — 873ms φ-pulse, metrics every 5th beat
// ═══════════════════════════════════════════════════════════════

var beatCount = 0;
var startMs   = Date.now();

setInterval(function () {
  beatCount++;

  var healthy = 0, degraded = 0, critical = 0;
  for (var i = 0; i < SYSTEM_NAMES.length; i++) {
    var s = SYSTEMS[SYSTEM_NAMES[i]].status;
    if (s === 'healthy')  healthy++;
    if (s === 'degraded') degraded++;
    if (s === 'critical') critical++;
  }

  var msg = {
    type:   'heartbeat',
    worker: 'infra-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalChecks:     totalChecks,
      healthySystems:  healthy,
      degradedSystems: degraded,
      criticalSystems: critical,
      totalScales:     totalScales,
      totalDeploys:    totalDeploys,
      totalRecovers:   totalRecovers,
      uptimeMs:        Date.now() - startMs,
    };
  }

  self.postMessage(msg);
}, HEARTBEAT_MS);

// ═══════════════════════════════════════════════════════════════
//  MESSAGE HANDLER
// ═══════════════════════════════════════════════════════════════

self.onmessage = function (e) {
  var msg = e.data;
  var cmd = msg.cmd || msg.type;
  var id  = msg.id;
  var result;

  switch (cmd) {
    // ── check — single system health check ─────────────────
    case 'check': {
      result = { ok: true, health: healthCheck(msg.system) };
      break;
    }

    // ── check_all — sweep all subsystems ───────────────────
    case 'check_all': {
      result = { ok: true, sweep: checkAll() };
      break;
    }

    // ── scale — auto-scale a system ────────────────────────
    case 'scale': {
      result = { ok: true, scale: autoScale(msg.system, msg.load, msg.capacity) };
      break;
    }

    // ── deploy — canary deployment ─────────────────────────
    case 'deploy': {
      result = { ok: true, deploy: deployCanary(msg.artifact, msg.weight) };
      break;
    }

    // ── recover — failover recovery ────────────────────────
    case 'recover': {
      result = { ok: true, recovery: recoverSystem(msg.system) };
      break;
    }

    // ── status — all systems status ────────────────────────
    case 'status': {
      var statuses = SYSTEM_NAMES.map(function(n) {
        var s = SYSTEMS[n];
        return { name: n, status: s.status, latencyMs: s.latencyMs, uptimeRatio: Math.round(s.uptimeRatio*10000)/10000, checks: s.checks };
      });
      result = { ok: true, systems: statuses, count: statuses.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:            true,
        systems:       SYSTEM_NAMES.length,
        totalChecks:   totalChecks,
        totalScales:   totalScales,
        totalDeploys:  totalDeploys,
        totalRecovers: totalRecovers,
        uptime:        beatCount * HEARTBEAT_MS,
        heartbeatMs:   HEARTBEAT_MS,
      };
      break;
    }

    default:
      result = { ok: false, error: 'unknown command: ' + cmd };
  }

  self.postMessage(Object.assign({}, result, { type: 'response', cmd: cmd, id: id, ts: Date.now() }));
};

// ═══════════════════════════════════════════════════════════════
//  BOOT
// ═══════════════════════════════════════════════════════════════

self.postMessage({
  type:        'boot',
  worker:      'infra-worker',
  systems:     SYSTEM_NAMES.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
