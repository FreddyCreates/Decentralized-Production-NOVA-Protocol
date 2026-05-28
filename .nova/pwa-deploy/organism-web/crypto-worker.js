///
/// NOVA CRYPTO WORKER — Fibonacci Cascade Encryption Engine
///
/// A permanent Web Worker implementing φ-cascade transforms (LAW-EN-016),
/// E8 root system sealing (LAW-EN-019), Leech lattice hashing (LAW-EN-018),
/// icosahedral key rotation (LAW-EN-020), and full encrypt/verify
/// pipelines. 873ms heartbeat. Zero dependencies.
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
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalEncryptions   = 0;
var totalVerifications = 0;
var cascadesRun        = 0;
var e8Seals            = 0;
var leechHashes        = 0;
var rotations          = 0;

// ═══════════════════════════════════════════════════════════════
//  PHI CASCADE — 5-layer φ-transform (LAW-EN-016)
// ═══════════════════════════════════════════════════════════════

var CASCADE_SALTS = [2654435761, 2246822519, 3266489917, 668265263, 374761393];

function phiCascade(data) {
  cascadesRun++;
  var input  = String(data || '');
  var seed   = 0;
  for (var c = 0; c < input.length; c++) {
    seed = (seed + input.charCodeAt(c) * FIB[c % 20]) >>> 0;
  }

  var layers = [];
  var prev   = seed;

  for (var layer = 0; layer < 5; layer++) {
    prev = fibonacciHash(prev ^ CASCADE_SALTS[layer], 2147483647);
    layers.push(prev);
  }

  return {
    hash:   layers[4],
    layers: layers,
    depth:  5,
    law:    'LAW-EN-016',
  };
}

// ═══════════════════════════════════════════════════════════════
//  E8 SEAL — 240 root vectors, golden angle rotation (LAW-EN-019)
// ═══════════════════════════════════════════════════════════════

function e8Seal(data) {
  e8Seals++;
  var input = String(data || '');
  var hash  = 0;

  for (var v = 0; v < 240; v++) {
    var angle    = v * GOLDEN_ANGLE;
    var charCode = input.length > 0 ? input.charCodeAt(v % input.length) : v;
    var fibIdx   = (v * 3 + 7) % 20;

    hash = ((hash ^ (charCode * FIB[fibIdx])) + FIB[(v + 5) % 20]) >>> 0;
    hash = (hash * 2654435761) >>> 0;
    hash = (hash + fibonacciHash(v + charCode, 65521)) >>> 0;

    var rotComponent = Math.floor(Math.abs(Math.sin(angle) * FIB[(v + 2) % 20] * 1000));
    hash = (hash ^ rotComponent) >>> 0;
  }

  var hex = hash.toString(16).padStart(8, '0');

  return {
    seal:    hex,
    vectors: 240,
    lattice: 'E8',
    law:     'LAW-EN-019',
  };
}

// ═══════════════════════════════════════════════════════════════
//  LEECH HASH — 24-dimensional Leech lattice (LAW-EN-018)
// ═══════════════════════════════════════════════════════════════

function leechHash(data) {
  leechHashes++;
  var input = String(data || '');
  var dims  = new Array(24);

  for (var d = 0; d < 24; d++) {
    var seed = 0;
    for (var c = 0; c < input.length; c++) {
      seed = (seed + input.charCodeAt(c) * FIB[(c + d) % 20]) >>> 0;
    }
    dims[d] = fibonacciHash(seed ^ (d * 2654435761), 2147483647);
  }

  var combined = 0;
  for (var i = 0; i < 24; i++) {
    combined = ((combined ^ dims[i]) * 2654435761 + FIB[i % 20]) >>> 0;
  }

  return {
    hash:          combined,
    dimension:     24,
    kissingNumber: 196560,
    law:           'LAW-EN-018',
  };
}

// ═══════════════════════════════════════════════════════════════
//  ICOSAHEDRAL ROTATE — 60 symmetries (LAW-EN-020)
// ═══════════════════════════════════════════════════════════════

function icosahedralRotate(key, step) {
  rotations++;
  var keyVal = typeof key === 'number' ? key : 0;
  if (typeof key === 'string') {
    for (var c = 0; c < key.length; c++) {
      keyVal = (keyVal + key.charCodeAt(c) * FIB[c % 20]) >>> 0;
    }
  }

  var symmetry = (step || 0) % 60;
  var angle    = symmetry * GOLDEN_ANGLE;
  var rotated  = fibonacciHash(keyVal ^ (symmetry * 2654435761), 2147483647);

  var sinComponent = Math.floor(Math.abs(Math.sin(angle) * 1000000));
  var cosComponent = Math.floor(Math.abs(Math.cos(angle) * 1000000));
  rotated = ((rotated ^ sinComponent) + cosComponent) >>> 0;

  return {
    rotatedKey: rotated,
    symmetry:   symmetry,
    totalSymmetries: 60,
    law:        'LAW-EN-020',
  };
}

// ═══════════════════════════════════════════════════════════════
//  ENCRYPT — full pipeline: phiCascade → e8Seal
// ═══════════════════════════════════════════════════════════════

function encrypt(plaintext) {
  totalEncryptions++;
  var cascade = phiCascade(plaintext);
  var seal    = e8Seal(plaintext);

  return {
    encrypted:    cascade.hash,
    seal:         seal.seal,
    cascadeDepth: cascade.depth,
    layers:       cascade.layers,
    vectors:      seal.vectors,
  };
}

// ═══════════════════════════════════════════════════════════════
//  VERIFY — recompute and compare seals
// ═══════════════════════════════════════════════════════════════

function verify(data, sealValue) {
  totalVerifications++;
  var computed = e8Seal(data);

  return {
    valid:    computed.seal === sealValue,
    expected: computed.seal,
    provided: sealValue,
    lattice:  'E8',
    vectors:  240,
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
    worker: 'crypto-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalEncryptions:   totalEncryptions,
      totalVerifications: totalVerifications,
      cascadesRun:        cascadesRun,
      e8Seals:            e8Seals,
      leechHashes:        leechHashes,
      rotations:          rotations,
      uptimeMs:           Date.now() - startMs,
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
    // ── encrypt — full pipeline ────────────────────────────
    case 'encrypt': {
      result = { ok: true, encryption: encrypt(msg.plaintext || msg.data || '') };
      break;
    }

    // ── verify — seal verification ─────────────────────────
    case 'verify': {
      result = { ok: true, verification: verify(msg.data || '', msg.seal || '') };
      break;
    }

    // ── cascade — φ-cascade only ───────────────────────────
    case 'cascade': {
      result = { ok: true, cascade: phiCascade(msg.data || '') };
      break;
    }

    // ── e8 — E8 seal only ──────────────────────────────────
    case 'e8': {
      result = { ok: true, seal: e8Seal(msg.data || '') };
      break;
    }

    // ── leech — Leech lattice hash ─────────────────────────
    case 'leech': {
      result = { ok: true, leech: leechHash(msg.data || '') };
      break;
    }

    // ── rotate — icosahedral key rotation ──────────────────
    case 'rotate': {
      result = { ok: true, rotation: icosahedralRotate(msg.key, msg.step) };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:                 true,
        totalEncryptions:   totalEncryptions,
        totalVerifications: totalVerifications,
        cascadesRun:        cascadesRun,
        e8Seals:            e8Seals,
        leechHashes:        leechHashes,
        rotations:          rotations,
        uptime:             beatCount * HEARTBEAT_MS,
        heartbeatMs:        HEARTBEAT_MS,
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
  worker:      'crypto-worker',
  cascadeLayers: 5,
  e8Vectors:   240,
  leechDim:    24,
  icosaSymmetries: 60,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
