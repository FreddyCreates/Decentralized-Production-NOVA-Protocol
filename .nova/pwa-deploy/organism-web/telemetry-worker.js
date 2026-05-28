///
/// NOVA TELEMETRY WORKER — 24/7 Organism Telemetry
///
/// A permanent Web Worker for real-time metrics aggregation,
/// anomaly detection using φ-deviation (LAW-OB-007), golden
/// sampling at φ-spaced intervals, and full statistical
/// snapshots. 873ms heartbeat. Zero dependencies.
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
//  RING BUFFER — fixed-capacity circular buffer
// ═══════════════════════════════════════════════════════════════

var RING_CAPACITY = 1000;

function createRingBuffer() {
  return { data: new Array(RING_CAPACITY), head: 0, size: 0 };
}

function ringPush(buf, value) {
  buf.data[buf.head] = value;
  buf.head = (buf.head + 1) % RING_CAPACITY;
  if (buf.size < RING_CAPACITY) buf.size++;
}

function ringValues(buf) {
  var out = [];
  var start = buf.size < RING_CAPACITY ? 0 : buf.head;
  for (var i = 0; i < buf.size; i++) {
    out.push(buf.data[(start + i) % RING_CAPACITY]);
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════
//  METRICS STORE — per-metric aggregation
// ═══════════════════════════════════════════════════════════════

var MetricsStore = {};
var totalRecords   = 0;
var totalAnomalies = 0;

function getOrCreate(name) {
  if (!safeKey(name)) return null;
  if (!MetricsStore[name]) {
    MetricsStore[name] = {
      ring:          createRingBuffer(),
      count:         0,
      sum:           0,
      min:           Infinity,
      max:           -Infinity,
      mean:          0,
      lastValue:     0,
      lastTimestamp:  0,
    };
  }
  return MetricsStore[name];
}

// ═══════════════════════════════════════════════════════════════
//  RECORD — add a value to a metric
// ═══════════════════════════════════════════════════════════════

function record(name, value) {
  totalRecords++;
  var m = getOrCreate(name);
  if (!m) return { name: name, error: 'invalid metric name', recorded: false };
  ringPush(m.ring, value);
  m.count++;
  m.sum += value;
  if (value < m.min) m.min = value;
  if (value > m.max) m.max = value;
  m.mean = m.sum / m.count;
  m.lastValue     = value;
  m.lastTimestamp  = Date.now();
  return { name: name, count: m.count, mean: Math.round(m.mean * 10000) / 10000, recorded: true };
}

// ═══════════════════════════════════════════════════════════════
//  AGGREGATE — full statistical summary
// ═══════════════════════════════════════════════════════════════

function aggregate(name) {
  var m = MetricsStore[name];
  if (!m) return { name: name, error: 'metric not found' };

  var vals = ringValues(m.ring);
  vals.sort(function(a, b) { return a - b; });
  var n = vals.length;

  var variance = 0;
  for (var i = 0; i < n; i++) {
    var d = vals[i] - m.mean;
    variance += d * d;
  }
  variance = n > 1 ? variance / (n - 1) : 0;
  var stddev = Math.sqrt(variance);

  var p50 = vals[Math.floor(n * 0.50)] || 0;
  var p95 = vals[Math.floor(n * 0.95)] || 0;
  var p99 = vals[Math.floor(n * 0.99)] || 0;

  var elapsedSec = (Date.now() - startMs) / 1000;
  var ratePerSec = elapsedSec > 0 ? m.count / elapsedSec : 0;

  return {
    name:        name,
    count:       m.count,
    sum:         Math.round(m.sum * 10000) / 10000,
    min:         m.min === Infinity ? 0 : m.min,
    max:         m.max === -Infinity ? 0 : m.max,
    mean:        Math.round(m.mean * 10000) / 10000,
    stddev:      Math.round(stddev * 10000) / 10000,
    p50:         p50,
    p95:         p95,
    p99:         p99,
    rate_per_sec: Math.round(ratePerSec * 10000) / 10000,
  };
}

// ═══════════════════════════════════════════════════════════════
//  ANOMALY DETECT — LAW-OB-007: |x - μ_H| > φ·σ
// ═══════════════════════════════════════════════════════════════

function anomalyDetect(name) {
  if (!safeKey(name)) return { name: name, error: 'invalid metric name' };
  var m = MetricsStore[name];
  if (!m) return { name: name, error: 'metric not found' };

  var vals = ringValues(m.ring);
  var n    = vals.length;
  if (n < 3) return { name: name, anomaly: false, reason: 'insufficient data' };

  // Harmonic mean
  var recipSum = 0;
  var validCount = 0;
  for (var i = 0; i < n; i++) {
    if (vals[i] !== 0) { recipSum += 1.0 / Math.abs(vals[i]); validCount++; }
  }
  var harmonicMean = validCount > 0 ? validCount / recipSum : 0;

  // Standard deviation
  var variance = 0;
  for (var j = 0; j < n; j++) {
    var d = vals[j] - m.mean;
    variance += d * d;
  }
  var stddev = Math.sqrt(n > 1 ? variance / (n - 1) : 0);

  var lastVal   = m.lastValue;
  var deviation = Math.abs(lastVal - harmonicMean);
  var threshold = PHI * stddev;
  var anomaly   = deviation > threshold;

  if (anomaly) totalAnomalies++;

  return {
    name:         name,
    anomaly:      anomaly,
    lastValue:    lastVal,
    harmonicMean: Math.round(harmonicMean * 10000) / 10000,
    stddev:       Math.round(stddev * 10000) / 10000,
    deviation:    Math.round(deviation * 10000) / 10000,
    threshold:    Math.round(threshold * 10000) / 10000,
    law:          'LAW-OB-007',
  };
}

// ═══════════════════════════════════════════════════════════════
//  GOLDEN SAMPLING — φ-spaced interval sampling
// ═══════════════════════════════════════════════════════════════

function goldenSample(name, sampleCount) {
  var m = MetricsStore[name];
  if (!m) return { name: name, error: 'metric not found' };

  var vals    = ringValues(m.ring);
  var n       = vals.length;
  var count   = sampleCount || 10;
  var samples = [];

  for (var i = 0; i < count && i < n; i++) {
    var idx = Math.floor((i * PHI_INVERSE * n) % n);
    samples.push({ index: idx, value: vals[idx] });
  }

  return { name: name, samples: samples, method: 'golden-ratio', spacing: PHI_INVERSE };
}

// ═══════════════════════════════════════════════════════════════
//  SNAPSHOT — all metrics summary
// ═══════════════════════════════════════════════════════════════

function snapshot() {
  var names = Object.keys(MetricsStore);
  var summaries = [];
  for (var i = 0; i < names.length; i++) {
    var m = MetricsStore[names[i]];
    summaries.push({
      name:      names[i],
      count:     m.count,
      mean:      Math.round(m.mean * 10000) / 10000,
      min:       m.min === Infinity ? 0 : m.min,
      max:       m.max === -Infinity ? 0 : m.max,
      lastValue: m.lastValue,
    });
  }
  return { metrics: summaries, activeMetrics: names.length, totalRecords: totalRecords };
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
    worker: 'telemetry-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalRecords:   totalRecords,
      totalAnomalies: totalAnomalies,
      activeMetrics:  Object.keys(MetricsStore).length,
      uptimeMs:       Date.now() - startMs,
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
    // ── record — add a metric value ────────────────────────
    case 'record': {
      result = { ok: true, record: record(msg.name, msg.value) };
      break;
    }

    // ── aggregate — full stats ─────────────────────────────
    case 'aggregate': {
      result = { ok: true, aggregate: aggregate(msg.name) };
      break;
    }

    // ── anomaly — LAW-OB-007 detection ─────────────────────
    case 'anomaly': {
      result = { ok: true, anomaly: anomalyDetect(msg.name) };
      break;
    }

    // ── snapshot — all metrics summary ─────────────────────
    case 'snapshot': {
      result = { ok: true, snapshot: snapshot() };
      break;
    }

    // ── sample — golden ratio sampling ─────────────────────
    case 'sample': {
      result = { ok: true, sample: goldenSample(msg.name, msg.count) };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:             true,
        totalRecords:   totalRecords,
        totalAnomalies: totalAnomalies,
        activeMetrics:  Object.keys(MetricsStore).length,
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
  type:        'boot',
  worker:      'telemetry-worker',
  ringCapacity: RING_CAPACITY,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
