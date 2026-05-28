///
/// NOVA MARKETPLACE WORKER — Dynamic Pricing & Call Market Engine
///
/// A permanent Web Worker for dynamic call pricing, invocation
/// tracking, and demand forecasting across 3 market surfaces.
/// 40 registered agent calls with Fibonacci-based cost classes.
/// 873ms heartbeat. Zero dependencies.
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

// ═══════════════════════════════════════════════════════════════
//  CALL SURFACES — 3 market surfaces
// ═══════════════════════════════════════════════════════════════

var CALL_SURFACES = [
  { id: 'SURF-INT', name: 'Internal',  markup: 1.0 },
  { id: 'SURF-DEV', name: 'Developer', markup: PHI_INVERSE },
  { id: 'SURF-AI',  name: 'AI-Native', markup: 1 / PHI / PHI },
];

// ═══════════════════════════════════════════════════════════════
//  CALLS — 40 registered agent calls
// ═══════════════════════════════════════════════════════════════

var COST_CLASSES = Object.create(null);
COST_CLASSES['free']       = 0;
COST_CLASSES['micro']      = 1;
COST_CLASSES['standard']   = 5;
COST_CLASSES['premium']    = 21;
COST_CLASSES['enterprise'] = 89;

var CALL_DEFS = [
  { name: 'orchestrate_external',  costClass: 'premium' },
  { name: 'integrate_partner',     costClass: 'standard' },
  { name: 'orchestrate_cloud',     costClass: 'premium' },
  { name: 'orchestrate_edge',      costClass: 'premium' },
  { name: 'command_exterior',      costClass: 'enterprise' },
  { name: 'crawl_web',             costClass: 'standard' },
  { name: 'index_content',         costClass: 'standard' },
  { name: 'extract_data',          costClass: 'standard' },
  { name: 'manage_cache',          costClass: 'micro' },
  { name: 'command_web',           costClass: 'enterprise' },
  { name: 'render_scene',          costClass: 'premium' },
  { name: 'composite_layers',      costClass: 'standard' },
  { name: 'rasterize_vectors',     costClass: 'standard' },
  { name: 'animate_sequence',      costClass: 'premium' },
  { name: 'command_rendering',     costClass: 'enterprise' },
  { name: 'build_tree',            costClass: 'micro' },
  { name: 'build_graph',           costClass: 'standard' },
  { name: 'process_stream',        costClass: 'standard' },
  { name: 'query_spatial',         costClass: 'premium' },
  { name: 'command_structures',    costClass: 'enterprise' },
  { name: 'execute_code',          costClass: 'standard' },
  { name: 'schedule_task',         costClass: 'micro' },
  { name: 'profile_runtime',       costClass: 'standard' },
  { name: 'manage_sandbox',        costClass: 'premium' },
  { name: 'command_runtime',       costClass: 'enterprise' },
  { name: 'select_model',          costClass: 'standard' },
  { name: 'fuse_models',           costClass: 'premium' },
  { name: 'evaluate_model',        costClass: 'standard' },
  { name: 'train_model',           costClass: 'enterprise' },
  { name: 'command_models',        costClass: 'enterprise' },
  { name: 'price_call',            costClass: 'free' },
  { name: 'audit_market',          costClass: 'micro' },
  { name: 'balance_load',          costClass: 'standard' },
  { name: 'enforce_contract',      costClass: 'premium' },
  { name: 'command_market',        costClass: 'enterprise' },
  { name: 'monitor_health',        costClass: 'free' },
  { name: 'auto_scale',            costClass: 'standard' },
  { name: 'deploy_artifact',       costClass: 'premium' },
  { name: 'recover_disaster',      costClass: 'enterprise' },
  { name: 'command_infrastructure', costClass: 'enterprise' },
];

var CALLS = [];
for (var ci = 0; ci < CALL_DEFS.length; ci++) {
  var def = CALL_DEFS[ci];
  var padded = String(ci + 1);
  while (padded.length < 3) padded = '0' + padded;
  CALLS.push({
    id:          'CALL-' + padded,
    name:        def.name,
    costClass:   def.costClass,
    basePrice:   COST_CLASSES[def.costClass],
    invocations: 0,
    revenue:     0,
  });
}

// ═══════════════════════════════════════════════════════════════
//  CALL INDEX — Map for safe lookups
// ═══════════════════════════════════════════════════════════════

var CallIndex = new Map();
for (var idx = 0; idx < CALLS.length; idx++) {
  CallIndex.set(CALLS[idx].id, CALLS[idx]);
}

var SurfaceIndex = new Map();
for (var si = 0; si < CALL_SURFACES.length; si++) {
  SurfaceIndex.set(CALL_SURFACES[si].id, CALL_SURFACES[si]);
}

// ═══════════════════════════════════════════════════════════════
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalInvocations = 0;
var totalRevenue     = 0;

// ═══════════════════════════════════════════════════════════════
//  PRICE — compute dynamic price for a call on a surface
// ═══════════════════════════════════════════════════════════════

function price(callId, surfaceId) {
  var call = CallIndex.get(callId);
  if (!call) return { error: 'call not found: ' + callId };

  var surface = SurfaceIndex.get(surfaceId || 'SURF-INT');
  if (!surface) return { error: 'surface not found: ' + surfaceId };

  var demandFactor = 1 + (call.invocations / 1000) * PHI_INVERSE;
  var computed     = call.basePrice * surface.markup * demandFactor;

  return {
    callId:       call.id,
    price:        Math.round(computed * 10000) / 10000,
    surface:      surface.id,
    demandFactor: Math.round(demandFactor * 10000) / 10000,
  };
}

// ═══════════════════════════════════════════════════════════════
//  INVOKE — record an invocation and collect revenue
// ═══════════════════════════════════════════════════════════════

function invoke(callId, surfaceId) {
  var call = CallIndex.get(callId);
  if (!call) return { error: 'call not found: ' + callId };

  var priceResult = price(callId, surfaceId);
  if (priceResult.error) return priceResult;

  call.invocations++;
  totalInvocations++;
  call.revenue += priceResult.price;
  totalRevenue += priceResult.price;

  return {
    callId:           call.id,
    price:            priceResult.price,
    totalInvocations: call.invocations,
    totalRevenue:     Math.round(call.revenue * 10000) / 10000,
  };
}

// ═══════════════════════════════════════════════════════════════
//  FORECAST — golden-growth demand forecast
// ═══════════════════════════════════════════════════════════════

function forecast(callId) {
  var call = CallIndex.get(callId);
  if (!call) return { error: 'call not found: ' + callId };

  var currentRate = call.invocations;
  var projected   = currentRate * PHI;

  return {
    callId:       call.id,
    currentRate:  currentRate,
    forecast:     Math.round(projected * 10000) / 10000,
    growthFactor: PHI,
  };
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
    worker: 'marketplace-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';

    var callsByClass = Object.create(null);
    callsByClass['free'] = 0;
    callsByClass['micro'] = 0;
    callsByClass['standard'] = 0;
    callsByClass['premium'] = 0;
    callsByClass['enterprise'] = 0;

    var topCalls = [];
    for (var i = 0; i < CALLS.length; i++) {
      callsByClass[CALLS[i].costClass]++;
      if (CALLS[i].invocations > 0) {
        topCalls.push({ id: CALLS[i].id, name: CALLS[i].name, invocations: CALLS[i].invocations });
      }
    }
    topCalls.sort(function (a, b) { return b.invocations - a.invocations; });
    topCalls = topCalls.slice(0, 5);

    msg.metrics = {
      totalInvocations: totalInvocations,
      totalRevenue:     Math.round(totalRevenue * 10000) / 10000,
      callsByClass:     callsByClass,
      topCalls:         topCalls,
      uptimeMs:         Date.now() - startMs,
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
    // ── price — compute dynamic price ──────────────────────
    case 'price': {
      result = { ok: true, pricing: price(msg.callId, msg.surface) };
      break;
    }

    // ── invoke — record invocation ─────────────────────────
    case 'invoke': {
      result = { ok: true, invocation: invoke(msg.callId, msg.surface) };
      break;
    }

    // ── forecast — demand forecast ─────────────────────────
    case 'forecast': {
      result = { ok: true, forecast: forecast(msg.callId) };
      break;
    }

    // ── calls — list all calls ─────────────────────────────
    case 'calls': {
      var callList = CALLS.map(function (c) {
        return {
          id:          c.id,
          name:        c.name,
          costClass:   c.costClass,
          basePrice:   c.basePrice,
          invocations: c.invocations,
          revenue:     Math.round(c.revenue * 10000) / 10000,
        };
      });
      result = { ok: true, calls: callList, count: callList.length };
      break;
    }

    // ── surfaces — list market surfaces ────────────────────
    case 'surfaces': {
      result = { ok: true, surfaces: CALL_SURFACES, count: CALL_SURFACES.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:               true,
        calls:            CALLS.length,
        surfaces:         CALL_SURFACES.length,
        totalInvocations: totalInvocations,
        totalRevenue:     Math.round(totalRevenue * 10000) / 10000,
        uptime:           beatCount * HEARTBEAT_MS,
        heartbeatMs:      HEARTBEAT_MS,
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
  worker:      'marketplace-worker',
  calls:       CALLS.length,
  surfaces:    CALL_SURFACES.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
