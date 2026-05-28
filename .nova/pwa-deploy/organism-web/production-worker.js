///
/// NOVA PRODUCTION WORKER — Product Lifecycle & CI/CD Orchestration
///
/// A permanent Web Worker for build pipeline simulation, quality
/// gate enforcement, deployment tracking, and rollback management.
/// 8 active products with 7-stage pipelines and φ-quality gates.
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
//  PRODUCTS — 8 active products (one per division house)
// ═══════════════════════════════════════════════════════════════

var PRODUCTS = [
  { id: 'PROD-001', name: 'Exterior Gateway',       division: 'exterior',       status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-002', name: 'Web Intelligence Suite',  division: 'web',            status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-003', name: 'Rendering Engine',        division: 'rendering',      status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-004', name: 'Data Structure Core',     division: 'data',           status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-005', name: 'Runtime Platform',        division: 'runtime',        status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-006', name: 'Model Laboratory',        division: 'models',         status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-007', name: 'Market Exchange',          division: 'market',         status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
  { id: 'PROD-008', name: 'Infrastructure Fabric',    division: 'infrastructure', status: 'production', version: '1.0.0', builds: 0, deploys: 0, quality: 1.0, lastBuild: 0 },
];

// ═══════════════════════════════════════════════════════════════
//  PIPELINE STAGES & QUALITY GATES
// ═══════════════════════════════════════════════════════════════

var PIPELINE_STAGES = ['source', 'build', 'test', 'security', 'stage', 'canary', 'production'];

var QUALITY_GATES = [];
for (var gi = 0; gi < PIPELINE_STAGES.length; gi++) {
  QUALITY_GATES.push({
    stage:     PIPELINE_STAGES[gi],
    threshold: Math.pow(PHI_INVERSE, gi),
  });
}

// ═══════════════════════════════════════════════════════════════
//  PRODUCT & ARTIFACT INDEXES — Maps for safe lookups
// ═══════════════════════════════════════════════════════════════

var ProductIndex = new Map();
for (var pi = 0; pi < PRODUCTS.length; pi++) {
  ProductIndex.set(PRODUCTS[pi].id, PRODUCTS[pi]);
}

var artifactStore = new Map();
var nextBuildId   = 1;

// ═══════════════════════════════════════════════════════════════
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalBuilds    = 0;
var totalDeploys   = 0;
var totalRollbacks = 0;

// ═══════════════════════════════════════════════════════════════
//  DETERMINISTIC PSEUDO-RANDOM — fibonacci-hash based
// ═══════════════════════════════════════════════════════════════

var prngState = 42;

function prngNext() {
  prngState = fibonacciHash(prngState + 1, 2147483647);
  return prngState / 2147483647;
}

// ═══════════════════════════════════════════════════════════════
//  BUILD — run product through pipeline stages
// ═══════════════════════════════════════════════════════════════

function build(productId) {
  var product = ProductIndex.get(productId);
  if (!product) return { error: 'product not found: ' + productId };

  totalBuilds++;
  product.builds++;
  product.lastBuild = Date.now();

  var buildId = 'BLD-' + nextBuildId++;
  var stages  = [];
  var allPassed = true;

  for (var s = 0; s < PIPELINE_STAGES.length; s++) {
    var gate      = QUALITY_GATES[s];
    var roll      = prngNext();
    var passed    = roll > (1.0 - gate.threshold * product.quality);
    var duration  = FIB[s + 3] * 10;

    stages.push({
      name:     PIPELINE_STAGES[s],
      passed:   passed,
      duration: duration,
    });

    if (!passed) {
      allPassed = false;
      break;
    }
  }

  var fibHash = fibonacciHash(parseInt(buildId.replace('BLD-', ''), 10), 2147483647);

  artifactStore.set(buildId, {
    productId: product.id,
    stages:    stages,
    hash:      fibHash,
    timestamp: Date.now(),
    version:   product.version,
    passed:    allPassed,
  });

  if (artifactStore.size > 200) {
    var firstKey = artifactStore.keys().next().value;
    artifactStore.delete(firstKey);
  }

  return {
    productId: product.id,
    buildId:   buildId,
    stages:    stages,
    allPassed: allPassed,
    fibHash:   fibHash,
  };
}

// ═══════════════════════════════════════════════════════════════
//  DEPLOY — deploy if last build passed
// ═══════════════════════════════════════════════════════════════

function deploy(productId) {
  var product = ProductIndex.get(productId);
  if (!product) return { error: 'product not found: ' + productId };

  var lastArtifact = null;
  artifactStore.forEach(function (v) {
    if (v.productId === productId) lastArtifact = v;
  });

  if (!lastArtifact || !lastArtifact.passed) {
    return { error: 'no passing build available for: ' + productId };
  }

  totalDeploys++;
  product.deploys++;

  var parts   = product.version.split('.');
  var patch   = parseInt(parts[2], 10) + 1;
  product.version = parts[0] + '.' + parts[1] + '.' + patch;
  product.status  = 'production';

  return {
    productId: product.id,
    version:   product.version,
    deployId:  'DPL-' + totalDeploys,
    timestamp: Date.now(),
  };
}

// ═══════════════════════════════════════════════════════════════
//  QUALITY GATE — check quality at a specific stage
// ═══════════════════════════════════════════════════════════════

function qualityGate(productId, stage) {
  var product = ProductIndex.get(productId);
  if (!product) return { error: 'product not found: ' + productId };

  var stageIdx = PIPELINE_STAGES.indexOf(stage);
  if (stageIdx === -1) return { error: 'unknown stage: ' + stage };

  var gate      = QUALITY_GATES[stageIdx];
  var passed    = product.quality >= gate.threshold;

  return {
    productId: product.id,
    stage:     stage,
    quality:   Math.round(product.quality * 10000) / 10000,
    threshold: Math.round(gate.threshold * 10000) / 10000,
    passed:    passed,
  };
}

// ═══════════════════════════════════════════════════════════════
//  ROLLBACK — revert to previous version
// ═══════════════════════════════════════════════════════════════

function rollback(productId) {
  var product = ProductIndex.get(productId);
  if (!product) return { error: 'product not found: ' + productId };

  var parts   = product.version.split('.');
  var patch   = parseInt(parts[2], 10);
  if (patch <= 0) return { error: 'cannot rollback: already at base version' };

  totalRollbacks++;
  var previousVersion = product.version;
  product.version     = parts[0] + '.' + parts[1] + '.' + (patch - 1);
  product.status      = 'rolled-back';

  return {
    productId:       product.id,
    rolledBack:      true,
    previousVersion: previousVersion,
    currentVersion:  product.version,
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
    worker: 'production-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';

    var totalQuality = 0;
    var productsByStatus = Object.create(null);
    for (var i = 0; i < PRODUCTS.length; i++) {
      totalQuality += PRODUCTS[i].quality;
      var st = PRODUCTS[i].status;
      if (!(st in productsByStatus)) productsByStatus[st] = 0;
      productsByStatus[st]++;
    }

    msg.metrics = {
      totalBuilds:      totalBuilds,
      totalDeploys:     totalDeploys,
      totalRollbacks:   totalRollbacks,
      avgQuality:       Math.round((totalQuality / PRODUCTS.length) * 10000) / 10000,
      productsByStatus: productsByStatus,
      artifacts:        artifactStore.size,
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
    // ── build — run build pipeline ─────────────────────────
    case 'build': {
      result = { ok: true, build: build(msg.productId) };
      break;
    }

    // ── deploy — deploy product ────────────────────────────
    case 'deploy': {
      result = { ok: true, deployment: deploy(msg.productId) };
      break;
    }

    // ── gate — check quality gate ──────────────────────────
    case 'gate': {
      result = { ok: true, gate: qualityGate(msg.productId, msg.stage) };
      break;
    }

    // ── rollback — rollback product ────────────────────────
    case 'rollback': {
      result = { ok: true, rollback: rollback(msg.productId) };
      break;
    }

    // ── products — list all products ───────────────────────
    case 'products': {
      var prodList = PRODUCTS.map(function (p) {
        return {
          id:       p.id,
          name:     p.name,
          division: p.division,
          status:   p.status,
          version:  p.version,
          builds:   p.builds,
          deploys:  p.deploys,
          quality:  Math.round(p.quality * 10000) / 10000,
        };
      });
      result = { ok: true, products: prodList, count: prodList.length };
      break;
    }

    // ── artifacts — list artifact store ─────────────────────
    case 'artifacts': {
      var artList = [];
      artifactStore.forEach(function (v, k) {
        artList.push({ buildId: k, productId: v.productId, passed: v.passed, version: v.version, timestamp: v.timestamp });
      });
      result = { ok: true, artifacts: artList, count: artList.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:             true,
        products:       PRODUCTS.length,
        pipelineStages: PIPELINE_STAGES.length,
        totalBuilds:    totalBuilds,
        totalDeploys:   totalDeploys,
        totalRollbacks: totalRollbacks,
        artifacts:      artifactStore.size,
        uptime:         beatCount * HEARTBEAT_MS,
        heartbeatMs:    HEARTBEAT_MS,
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
  type:           'boot',
  worker:         'production-worker',
  products:       PRODUCTS.length,
  pipelineStages: PIPELINE_STAGES.length,
  heartbeatMs:    HEARTBEAT_MS,
  phi:            PHI,
  ts:             Date.now(),
});
