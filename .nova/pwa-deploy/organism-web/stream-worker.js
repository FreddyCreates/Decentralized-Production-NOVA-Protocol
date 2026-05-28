///
/// NOVA STREAM WORKER — Real-Time Data Stream Processing
///
/// A permanent Web Worker for ring-buffered stream channels,
/// φ-windowed event aggregation, append-only event logging with
/// fibonacci-hash chaining, and channel replay. 9 channels
/// (one per ring). 873ms heartbeat. Zero dependencies.
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
//  STREAM CHANNELS — 9 channels (one per ring)
// ═══════════════════════════════════════════════════════════════

var STREAM_CHANNELS = [
  'interface', 'sovereign', 'memory', 'build',
  'geometry', 'transport', 'proof', 'native', 'counsel',
];

var VALID_CHANNELS = new Map();
for (var chi = 0; chi < STREAM_CHANNELS.length; chi++) {
  VALID_CHANNELS.set(STREAM_CHANNELS[chi], true);
}

// ═══════════════════════════════════════════════════════════════
//  RING BUFFER — fixed-capacity circular buffer (987 = Fibonacci)
// ═══════════════════════════════════════════════════════════════

function RingBuffer(capacity) {
  this.buffer   = new Array(capacity);
  this.capacity = capacity;
  this.head     = 0;
  this.tail     = 0;
  this.size     = 0;
}

RingBuffer.prototype.push = function (item) {
  this.buffer[this.tail] = item;
  this.tail = (this.tail + 1) % this.capacity;
  if (this.size < this.capacity) {
    this.size++;
  } else {
    this.head = (this.head + 1) % this.capacity;
  }
};

RingBuffer.prototype.pop = function () {
  if (this.size === 0) return undefined;
  var item  = this.buffer[this.head];
  this.head = (this.head + 1) % this.capacity;
  this.size--;
  return item;
};

RingBuffer.prototype.peek = function () {
  if (this.size === 0) return undefined;
  return this.buffer[this.head];
};

RingBuffer.prototype.isFull = function () {
  return this.size === this.capacity;
};

RingBuffer.prototype.toArray = function () {
  var arr = [];
  var idx = this.head;
  for (var i = 0; i < this.size; i++) {
    arr.push(this.buffer[idx]);
    idx = (idx + 1) % this.capacity;
  }
  return arr;
};

// ═══════════════════════════════════════════════════════════════
//  STREAMS — Map of channel → RingBuffer
// ═══════════════════════════════════════════════════════════════

var RING_CAPACITY = 987;

var Streams = new Map();
for (var si = 0; si < STREAM_CHANNELS.length; si++) {
  Streams.set(STREAM_CHANNELS[si], new RingBuffer(RING_CAPACITY));
}

// ═══════════════════════════════════════════════════════════════
//  EVENT LOG — append-only, fibonacci-hash chained
// ═══════════════════════════════════════════════════════════════

var EventLog      = [];
var nextEventId   = 1;
var lastEventHash = 0;

// ═══════════════════════════════════════════════════════════════
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalPushed     = 0;
var totalWindowed   = 0;
var totalAggregated = 0;

// ═══════════════════════════════════════════════════════════════
//  PUSH — push event to channel's ring buffer + event log
// ═══════════════════════════════════════════════════════════════

function push(channel, event) {
  if (!VALID_CHANNELS.has(channel)) return { error: 'unknown channel: ' + channel };

  totalPushed++;

  var logId     = nextEventId++;
  var timestamp = Date.now();
  var eventStr  = typeof event === 'string' ? event : JSON.stringify(event);

  var entryVal = timestamp + eventStr.length + logId;
  var fibHash  = fibonacciHash((entryVal ^ lastEventHash) >>> 0, 2147483647);
  lastEventHash = fibHash;

  var entry = {
    id:        logId,
    channel:   channel,
    event:     event,
    timestamp: timestamp,
    fibHash:   fibHash,
  };

  Streams.get(channel).push(entry);
  EventLog.push(entry);
  if (EventLog.length > 5000) EventLog.shift();

  return {
    channel:  channel,
    buffered: Streams.get(channel).size,
    logId:    logId,
  };
}

// ═══════════════════════════════════════════════════════════════
//  WINDOW — retrieve events within a time window (φ-windowing)
// ═══════════════════════════════════════════════════════════════

function window(channel, durationMs) {
  if (!VALID_CHANNELS.has(channel)) return { error: 'unknown channel: ' + channel };

  totalWindowed++;

  var dur        = durationMs || 10000;
  var actualWin  = dur * PHI;
  var cutoff     = Date.now() - actualWin;
  var buffer     = Streams.get(channel);
  var all        = buffer.toArray();
  var events     = [];

  for (var i = 0; i < all.length; i++) {
    if (all[i].timestamp >= cutoff) {
      events.push(all[i]);
    }
  }

  return {
    channel:  channel,
    events:   events,
    count:    events.length,
    windowMs: Math.round(actualWin),
  };
}

// ═══════════════════════════════════════════════════════════════
//  AGGREGATE — aggregate events in a time window
// ═══════════════════════════════════════════════════════════════

function aggregate(channel, windowMs) {
  if (!VALID_CHANNELS.has(channel)) return { error: 'unknown channel: ' + channel };

  totalAggregated++;

  var win       = window(channel, windowMs);
  if (win.error) return win;

  var distinct  = new Map();
  for (var i = 0; i < win.events.length; i++) {
    var key = typeof win.events[i].event === 'string' ? win.events[i].event : JSON.stringify(win.events[i].event);
    distinct.set(key, true);
  }

  var durationSec = (win.windowMs || 1) / 1000;
  var rate        = win.count / durationSec;

  return {
    channel:  channel,
    count:    win.count,
    rate:     Math.round(rate * 10000) / 10000,
    distinct: distinct.size,
    windowMs: win.windowMs,
  };
}

// ═══════════════════════════════════════════════════════════════
//  REPLAY — replay events from log between IDs
// ═══════════════════════════════════════════════════════════════

function replay(channel, fromId, toId) {
  if (!VALID_CHANNELS.has(channel)) return { error: 'unknown channel: ' + channel };

  var from   = fromId || 1;
  var to     = toId || nextEventId - 1;
  var events = [];

  for (var i = 0; i < EventLog.length; i++) {
    var entry = EventLog[i];
    if (entry.channel === channel && entry.id >= from && entry.id <= to) {
      events.push(entry);
    }
  }

  return {
    channel: channel,
    events:  events,
    count:   events.length,
  };
}

// ═══════════════════════════════════════════════════════════════
//  SNAPSHOT — all channel states
// ═══════════════════════════════════════════════════════════════

function snapshot() {
  var channels = [];
  for (var i = 0; i < STREAM_CHANNELS.length; i++) {
    var name   = STREAM_CHANNELS[i];
    var buffer = Streams.get(name);
    var arr    = buffer.toArray();

    var oldestMs = 0;
    var newestMs = 0;
    if (arr.length > 0) {
      oldestMs = arr[0].timestamp;
      newestMs = arr[arr.length - 1].timestamp;
    }

    channels.push({
      name:     name,
      size:     buffer.size,
      capacity: buffer.capacity,
      oldestMs: oldestMs,
      newestMs: newestMs,
    });
  }

  return { channels: channels };
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
    worker: 'stream-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';

    var channelSizes = Object.create(null);
    for (var i = 0; i < STREAM_CHANNELS.length; i++) {
      channelSizes[STREAM_CHANNELS[i]] = Streams.get(STREAM_CHANNELS[i]).size;
    }

    msg.metrics = {
      totalPushed:     totalPushed,
      totalWindowed:   totalWindowed,
      totalAggregated: totalAggregated,
      channelSizes:    channelSizes,
      eventLogSize:    EventLog.length,
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
    // ── push — push event to channel ───────────────────────
    case 'push': {
      result = { ok: true, push: push(msg.channel, msg.event) };
      break;
    }

    // ── window — get events in time window ─────────────────
    case 'window': {
      result = { ok: true, window: window(msg.channel, msg.durationMs) };
      break;
    }

    // ── aggregate — aggregate events ───────────────────────
    case 'aggregate': {
      result = { ok: true, aggregation: aggregate(msg.channel, msg.windowMs) };
      break;
    }

    // ── replay — replay events from log ────────────────────
    case 'replay': {
      result = { ok: true, replay: replay(msg.channel, msg.fromId, msg.toId) };
      break;
    }

    // ── snapshot — all channel states ──────────────────────
    case 'snapshot': {
      result = { ok: true, snapshot: snapshot() };
      break;
    }

    // ── channels — list channel names ──────────────────────
    case 'channels': {
      result = { ok: true, channels: STREAM_CHANNELS, count: STREAM_CHANNELS.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:              true,
        channels:        STREAM_CHANNELS.length,
        ringCapacity:    RING_CAPACITY,
        totalPushed:     totalPushed,
        totalWindowed:   totalWindowed,
        totalAggregated: totalAggregated,
        eventLogSize:    EventLog.length,
        uptime:          beatCount * HEARTBEAT_MS,
        heartbeatMs:     HEARTBEAT_MS,
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
  type:         'boot',
  worker:       'stream-worker',
  channels:     STREAM_CHANNELS.length,
  ringCapacity: RING_CAPACITY,
  heartbeatMs:  HEARTBEAT_MS,
  phi:          PHI,
  ts:           Date.now(),
});
