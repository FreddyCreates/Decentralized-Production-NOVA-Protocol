///
/// NOVA SCHEDULER WORKER — Fibonacci Task Scheduling Engine
///
/// A permanent Web Worker for φ-priority task scheduling,
/// Fibonacci epoch boundaries (LAW-CO-035), work stealing,
/// named queues, and batch execution. 873ms heartbeat.
/// Zero dependencies.
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
//  EPOCH BOUNDARIES — Fibonacci numbers (LAW-CO-035)
// ═══════════════════════════════════════════════════════════════

var EPOCH_BOUNDARIES = [1,2,3,5,8,13,21,34,55,89,144,233,377,610,987];

// ═══════════════════════════════════════════════════════════════
//  NAMED QUEUES
// ═══════════════════════════════════════════════════════════════

var QUEUE_NAMES = ['default','high','low','background','critical'];

var Queues = {
  'default':    [],
  'high':       [],
  'low':        [],
  'background': [],
  'critical':   [],
};

// ═══════════════════════════════════════════════════════════════
//  COUNTERS & STATE
// ═══════════════════════════════════════════════════════════════

var nextTaskId     = 1;
var totalScheduled = 0;
var totalExecuted  = 0;
var totalStolen    = 0;
var totalWaitMs    = 0;
var currentEpoch   = 0;
var iterationCount = 0;

// ═══════════════════════════════════════════════════════════════
//  SCHEDULE — add task with φ-priority (LAW-SM-014)
// ═══════════════════════════════════════════════════════════════

function schedule(name, priority, queueName) {
  totalScheduled++;
  var p     = typeof priority === 'number' ? priority : 1;
  var queue = queueName && Queues[queueName] ? queueName : 'default';

  var task = {
    id:          nextTaskId++,
    name:        name || 'task-' + nextTaskId,
    priority:    p,
    phiPriority: 1.0 / Math.pow(PHI, p),
    scheduledAt: Date.now(),
    status:      'queued',
    result:      null,
    epoch:       currentEpoch,
    queue:       queue,
  };

  Queues[queue].push(task);
  sortQueue(queue);

  return {
    taskId:      task.id,
    name:        task.name,
    phiPriority: Math.round(task.phiPriority * 10000) / 10000,
    queue:       queue,
    scheduled:   true,
  };
}

function sortQueue(queueName) {
  Queues[queueName].sort(function(a, b) { return b.phiPriority - a.phiPriority; });
}

// ═══════════════════════════════════════════════════════════════
//  EXECUTE — pop and run highest priority task
// ═══════════════════════════════════════════════════════════════

function execute(queueName) {
  var queue = queueName || 'default';
  var q     = Queues[queue];
  if (!q || q.length === 0) return { executed: false, reason: 'queue empty', queue: queue };

  var task = q.shift();
  totalExecuted++;
  iterationCount++;

  var waitMs = Date.now() - task.scheduledAt;
  totalWaitMs += waitMs;

  var processingTime = FIB[task.priority % 20] * 10;
  task.status = 'running';

  var resultHash = fibonacciHash(task.id * task.priority + task.scheduledAt, 2147483647);
  task.status = 'done';
  task.result = resultHash;

  var epoch = epochCheck();

  return {
    executed:       true,
    taskId:         task.id,
    name:           task.name,
    result:         resultHash,
    processingMs:   processingTime,
    waitMs:         waitMs,
    queue:          queue,
    epoch:          epoch,
  };
}

// ═══════════════════════════════════════════════════════════════
//  BATCH EXECUTE — run top N tasks
// ═══════════════════════════════════════════════════════════════

function batchExecute(n, queueName) {
  var count   = n || 5;
  var results = [];
  for (var i = 0; i < count; i++) {
    var r = execute(queueName);
    results.push(r);
    if (!r.executed) break;
  }
  return { batch: results, executed: results.filter(function(r) { return r.executed; }).length };
}

// ═══════════════════════════════════════════════════════════════
//  WORK STEALING — take lowest-priority from another queue
// ═══════════════════════════════════════════════════════════════

function steal(fromQueue, toQueue) {
  var from = fromQueue || 'low';
  var to   = toQueue   || 'default';

  var srcQ = Queues[from];
  if (!srcQ || srcQ.length === 0) return { stolen: false, reason: 'source queue empty', from: from };

  var task = srcQ.pop();
  task.queue = to;
  totalStolen++;
  Queues[to].push(task);
  sortQueue(to);

  return {
    stolen:   true,
    taskId:   task.id,
    name:     task.name,
    from:     from,
    to:       to,
  };
}

// ═══════════════════════════════════════════════════════════════
//  EPOCH CHECK — Fibonacci-numbered iteration checkpoints
// ═══════════════════════════════════════════════════════════════

function epochCheck() {
  var isEpoch = false;
  for (var i = 0; i < EPOCH_BOUNDARIES.length; i++) {
    if (iterationCount === EPOCH_BOUNDARIES[i]) {
      currentEpoch++;
      isEpoch = true;
      break;
    }
  }
  return {
    isEpoch:        isEpoch,
    epochNumber:    currentEpoch,
    iteration:      iterationCount,
    tasksCompleted: totalExecuted,
    law:            'LAW-CO-035',
  };
}

// ═══════════════════════════════════════════════════════════════
//  QUEUE DEPTHS
// ═══════════════════════════════════════════════════════════════

function queueDepths() {
  var depths = {};
  for (var i = 0; i < QUEUE_NAMES.length; i++) {
    depths[QUEUE_NAMES[i]] = Queues[QUEUE_NAMES[i]].length;
  }
  return depths;
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
    worker: 'scheduler-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalScheduled: totalScheduled,
      totalExecuted:  totalExecuted,
      totalStolen:    totalStolen,
      avgWaitMs:      totalExecuted > 0 ? Math.round(totalWaitMs / totalExecuted) : 0,
      queueDepths:    queueDepths(),
      currentEpoch:   currentEpoch,
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
    // ── schedule — add a task ──────────────────────────────
    case 'schedule': {
      result = { ok: true, task: schedule(msg.name, msg.priority, msg.queue) };
      break;
    }

    // ── execute — run next task ────────────────────────────
    case 'execute': {
      result = { ok: true, execution: execute(msg.queue) };
      break;
    }

    // ── batch — run N tasks ────────────────────────────────
    case 'batch': {
      result = { ok: true, batch: batchExecute(msg.count, msg.queue) };
      break;
    }

    // ── steal — work stealing ──────────────────────────────
    case 'steal': {
      result = { ok: true, steal: steal(msg.from, msg.to) };
      break;
    }

    // ── queues — list queue depths ─────────────────────────
    case 'queues': {
      result = { ok: true, queues: queueDepths(), names: QUEUE_NAMES };
      break;
    }

    // ── epoch — check epoch status ─────────────────────────
    case 'epoch': {
      result = { ok: true, epoch: epochCheck() };
      break;
    }

    // ── stats — scheduler statistics ───────────────────────
    case 'stats': {
      result = {
        ok:             true,
        totalScheduled: totalScheduled,
        totalExecuted:  totalExecuted,
        totalStolen:    totalStolen,
        avgWaitMs:      totalExecuted > 0 ? Math.round(totalWaitMs / totalExecuted) : 0,
        queueDepths:    queueDepths(),
        currentEpoch:   currentEpoch,
        iterations:     iterationCount,
      };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:             true,
        totalScheduled: totalScheduled,
        totalExecuted:  totalExecuted,
        totalStolen:    totalStolen,
        queueNames:     QUEUE_NAMES,
        currentEpoch:   currentEpoch,
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
  type:          'boot',
  worker:        'scheduler-worker',
  queues:        QUEUE_NAMES.length,
  epochBoundaries: EPOCH_BOUNDARIES.length,
  heartbeatMs:   HEARTBEAT_MS,
  phi:           PHI,
  ts:            Date.now(),
});
