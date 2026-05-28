///
/// NOVA CONTRACT WORKER — Sovereign Contract & SLA Enforcement
///
/// A permanent Web Worker for SLA enforcement, token-bucket rate
/// limiting with φ-refill, and append-only fibonacci-hashed audit
/// logs. 873ms heartbeat. Zero dependencies.
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
//  SLA CONTRACTS — 8 standard contracts
// ═══════════════════════════════════════════════════════════════

var CONTRACTS = [
  { id: 'SLA-001', name: 'Engine Availability',     target: 0.999,  metric: 'uptime',            penaltyPhi: PHI },
  { id: 'SLA-002', name: 'Routing Latency',         target: 100,    metric: 'latency_ms',        penaltyPhi: PHI_INVERSE },
  { id: 'SLA-003', name: 'Safety Scan Rate',        target: 0.995,  metric: 'scan_success_rate', penaltyPhi: PHI },
  { id: 'SLA-004', name: 'Memory Retrieval',        target: 50,     metric: 'retrieval_ms',      penaltyPhi: PHI_INVERSE },
  { id: 'SLA-005', name: 'Consensus Threshold',     target: 0.667,  metric: 'consensus_rate',    penaltyPhi: PHI * PHI },
  { id: 'SLA-006', name: 'Encryption Throughput',   target: 1000,   metric: 'encryptions_per_s', penaltyPhi: PHI_INVERSE },
  { id: 'SLA-007', name: 'Agent Response Time',     target: 200,    metric: 'agent_latency_ms',  penaltyPhi: PHI },
  { id: 'SLA-008', name: 'Extension Invocation',    target: 0.998,  metric: 'ext_success_rate',  penaltyPhi: PHI_INVERSE },
];

// ═══════════════════════════════════════════════════════════════
//  CONTRACT STATE — per-contract tracking
// ═══════════════════════════════════════════════════════════════

var ContractState = {};

for (var ci = 0; ci < CONTRACTS.length; ci++) {
  ContractState[CONTRACTS[ci].id] = {
    violations: 0,
    checks:     0,
    lastCheck:  0,
    status:     'active',
    history:    [],
  };
}

var totalEnforcements = 0;
var totalViolations   = 0;

// ═══════════════════════════════════════════════════════════════
//  ENFORCE — check SLA compliance
// ═══════════════════════════════════════════════════════════════

function enforce(contractId, actualValue) {
  totalEnforcements++;

  var contract = null;
  for (var i = 0; i < CONTRACTS.length; i++) {
    if (CONTRACTS[i].id === contractId) { contract = CONTRACTS[i]; break; }
  }
  if (!contract) return { error: 'contract not found: ' + contractId };
  if (!safeKey(contractId)) return { error: 'invalid contract id' };

  var state = ContractState[contractId];
  state.checks++;
  state.lastCheck = Date.now();

  var isLatency = contract.metric.indexOf('_ms') !== -1 || contract.metric.indexOf('_per_s') !== -1;
  var met;
  if (isLatency && contract.metric.indexOf('_per_s') !== -1) {
    met = actualValue >= contract.target;
  } else if (isLatency) {
    met = actualValue <= contract.target;
  } else {
    met = actualValue >= contract.target;
  }

  var violation = null;
  var penalty   = 0;

  if (!met) {
    state.violations++;
    totalViolations++;
    state.status = 'breached';
    penalty = contract.penaltyPhi * state.violations;
    violation = {
      contractId: contractId,
      expected:   contract.target,
      actual:     actualValue,
      violation:  state.violations,
      penalty:    Math.round(penalty * 10000) / 10000,
    };
  }

  var entry = {
    timestamp:  Date.now(),
    contractId: contractId,
    met:        met,
    actual:     actualValue,
  };
  state.history.push(entry);
  if (state.history.length > 100) state.history.shift();

  appendAuditLog('enforce', contractId, met ? 'pass' : 'breach');

  return {
    met:       met,
    violation: violation,
    penalty:   Math.round(penalty * 10000) / 10000,
    checks:    state.checks,
    status:    state.status,
  };
}

// ═══════════════════════════════════════════════════════════════
//  RATE LIMITER — token bucket with φ-refill
// ═══════════════════════════════════════════════════════════════

var RateLimitBuckets = {};

function rateLimit(callName, maxPerSec) {
  var now = Date.now();
  var max = maxPerSec || 10;
  if (!safeKey(callName)) return { allowed: false, error: 'invalid call name' };

  if (!RateLimitBuckets[callName]) {
    RateLimitBuckets[callName] = {
      tokens:     max,
      maxTokens:  max,
      lastRefill: now,
      refillRate: PHI_INVERSE,
    };
  }

  var bucket = RateLimitBuckets[callName];

  var elapsedSec = (now - bucket.lastRefill) / 1000;
  var refill     = elapsedSec * bucket.refillRate * bucket.maxTokens;
  bucket.tokens  = Math.min(bucket.maxTokens, bucket.tokens + refill);
  bucket.lastRefill = now;

  if (bucket.tokens >= 1) {
    bucket.tokens--;
    return { allowed: true, remaining: Math.floor(bucket.tokens), callName: callName };
  }

  return { allowed: false, remaining: 0, callName: callName, retryAfterMs: Math.ceil(1000 / (bucket.refillRate * bucket.maxTokens)) };
}

// ═══════════════════════════════════════════════════════════════
//  AUDIT LOG — append-only, fibonacci-hash chained
// ═══════════════════════════════════════════════════════════════

var auditLog      = [];
var lastAuditHash = 0;

function appendAuditLog(action, contractId, result) {
  var entry = {
    timestamp:  Date.now(),
    action:     action,
    contractId: contractId,
    result:     result,
    prevHash:   lastAuditHash,
  };

  var entryVal = entry.timestamp + entry.action.length + (entry.contractId || '').length;
  entry.fibHash = fibonacciHash((entryVal ^ lastAuditHash) >>> 0, 2147483647);
  lastAuditHash = entry.fibHash;

  auditLog.push(entry);
  if (auditLog.length > 500) auditLog.shift();

  return entry;
}

// ═══════════════════════════════════════════════════════════════
//  HEARTBEAT — 873ms φ-pulse, metrics every 5th beat
// ═══════════════════════════════════════════════════════════════

var beatCount = 0;
var startMs   = Date.now();

setInterval(function () {
  beatCount++;
  var msg = {
    type:   'heartbeat',
    worker: 'contract-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalEnforcements: totalEnforcements,
      totalViolations:   totalViolations,
      contracts:         CONTRACTS.length,
      auditEntries:      auditLog.length,
      rateBuckets:       Object.keys(RateLimitBuckets).length,
      uptimeMs:          Date.now() - startMs,
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
    // ── enforce — check SLA compliance ─────────────────────
    case 'enforce': {
      result = { ok: true, enforcement: enforce(msg.contractId, msg.value) };
      break;
    }

    // ── rate_limit — token bucket check ────────────────────
    case 'rate_limit': {
      result = { ok: true, rateLimit: rateLimit(msg.callName, msg.maxPerSec) };
      break;
    }

    // ── audit — get audit log ──────────────────────────────
    case 'audit': {
      var count = msg.count || 20;
      var tail  = auditLog.slice(-count);
      result = { ok: true, audit: tail, total: auditLog.length };
      break;
    }

    // ── contracts — list all contracts ─────────────────────
    case 'contracts': {
      var list = CONTRACTS.map(function(c) {
        var st = ContractState[c.id];
        return {
          id:         c.id,
          name:       c.name,
          target:     c.target,
          metric:     c.metric,
          status:     st.status,
          checks:     st.checks,
          violations: st.violations,
        };
      });
      result = { ok: true, contracts: list, count: list.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:                true,
        contracts:         CONTRACTS.length,
        totalEnforcements: totalEnforcements,
        totalViolations:   totalViolations,
        auditEntries:      auditLog.length,
        rateBuckets:       Object.keys(RateLimitBuckets).length,
        uptime:            beatCount * HEARTBEAT_MS,
        heartbeatMs:       HEARTBEAT_MS,
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
  worker:      'contract-worker',
  contracts:   CONTRACTS.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
