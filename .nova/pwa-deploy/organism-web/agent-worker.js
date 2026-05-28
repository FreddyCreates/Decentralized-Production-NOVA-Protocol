///
/// NOVA AGENT WORKER — The 40 Alpha Agents
///
/// A permanent Web Worker running all 40 Alpha Agents from the organism.
/// Organised into 8 divisions, each with a Commander and Specialists.
/// Fibonacci-scheduled task dispatch. 873ms heartbeat. Zero dependencies.
///

// ══════════════════════════════════════════════════════════════════
//  GOLDEN CONSTANTS
// ══════════════════════════════════════════════════════════════════

const PHI           = 1.6180339887498948482;
const PHI_INVERSE   = 0.6180339887498948482;
const GOLDEN_ANGLE  = 2.39996322972865332;
const HEARTBEAT_MS  = 873;
const TWO_PI        = 2 * Math.PI;

const FIB = [1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765];

function fibonacciHash(n, mod) {
  let h = n;
  for (let i = 0; i < 5; i++) {
    h = ((h * FIB[(n + i) % 20]) ^ (FIB[(h + i) % 20] * 2654435761)) >>> 0;
    h = (h + FIB[(i * 3 + 7) % 20]) >>> 0;
  }
  return h % mod;
}

// ══════════════════════════════════════════════════════════════════
//  TIER WEIGHTS — φ-scaled by rank
// ══════════════════════════════════════════════════════════════════

const TIER_WEIGHT = {
  'AGI-Commander': PHI * PHI,          // ≈ 2.618
  'Commander':     PHI,                // ≈ 1.618
  'Specialist':    1.0,
  'Worker':        PHI_INVERSE,        // ≈ 0.618
};

const TIER_PROCESSING_MS = {
  'AGI-Commander': 34,
  'Commander':     21,
  'Specialist':    13,
  'Worker':        8,
};

// ══════════════════════════════════════════════════════════════════
//  AGENT REGISTRY — All 40 Alpha Agents
// ══════════════════════════════════════════════════════════════════

function makeAgent(id, name, latin, division, tier, call, reliability, maxConcurrent) {
  const seq = parseInt(id.replace('AGT-', ''), 10);
  return {
    id,
    name,
    latin,
    division,
    tier,
    call,
    reliability,
    maxConcurrent,
    always_running: true,
    status: 'active',
    phiWeight:    TIER_WEIGHT[tier] || 1.0,
    fibIdentity:  FIB[seq % 20],
    taskCount:    0,
    lastTask:     0,
    phase:        (seq * GOLDEN_ANGLE) % TWO_PI,
  };
}

const AGENTS = [
  // ── Exterior Orchestrators ──────────────────────────────────────
  makeAgent('AGT-001','Praetor','Praetor Orchestrationis Externae','Exterior Orchestrators','Commander','orchestrate_external',0.997,50),
  makeAgent('AGT-002','Legatus','Legatus Integrationis Sociorum','Exterior Orchestrators','Specialist','integrate_partner',0.995,20),
  makeAgent('AGT-003','Proconsul','Proconsul Nubium Multiplicium','Exterior Orchestrators','Specialist','orchestrate_cloud',0.999,10),
  makeAgent('AGT-004','Praefectus','Praefectus Flotae Marginalis','Exterior Orchestrators','Specialist','orchestrate_edge',0.993,100),
  makeAgent('AGT-005','Imperator Externus','Imperator AGI Orchestrationis Externae','Exterior Orchestrators','AGI-Commander','command_exterior',0.9999,5),

  // ── Web Workers ─────────────────────────────────────────────────
  makeAgent('AGT-006','Aranea','Aranea Exploratrix Retis','Web Workers','Specialist','crawl_web',0.985,200),
  makeAgent('AGT-007','Indexator','Indexator Contentuum Retis','Web Workers','Specialist','index_content',0.998,50),
  makeAgent('AGT-008','Extractor','Extractor Datorum Structorum','Web Workers','Specialist','extract_data',0.990,500),
  makeAgent('AGT-009','Cacheator','Cacheator Marginis Retis','Web Workers','Worker','manage_cache',0.999,1000),
  makeAgent('AGT-010','Imperator Retis','Imperator AGI Operationum Retis','Web Workers','AGI-Commander','command_web',0.998,5),

  // ── Rendering Workers ───────────────────────────────────────────
  makeAgent('AGT-011','Pictor Scaenici','Pictor Scaenicorum Trium Dimensionum','Rendering Workers','Specialist','render_scene',0.995,20),
  makeAgent('AGT-012','Compositor','Compositor Stratorum Multiplicium','Rendering Workers','Specialist','composite_layers',0.998,50),
  makeAgent('AGT-013','Rasterizator','Rasterizator Vectorum GPU','Rendering Workers','Worker','rasterize_vectors',0.999,200),
  makeAgent('AGT-014','Animans','Animans Motus Temporalis','Rendering Workers','Specialist','animate_sequence',0.996,30),
  makeAgent('AGT-015','Imperator Visualis','Imperator AGI Reddendi Universalis','Rendering Workers','AGI-Commander','command_rendering',0.999,3),

  // ── Data Structure Workers ──────────────────────────────────────
  makeAgent('AGT-016','Arbor','Arbor Structurarum Arboreum','Data Structure Workers','Specialist','build_tree',0.9999,500),
  makeAgent('AGT-017','Graphus','Graphus Reticulorum Datorum','Data Structure Workers','Specialist','build_graph',0.998,100),
  makeAgent('AGT-018','Fluvius','Fluvius Fluxuum Datorum','Data Structure Workers','Worker','process_stream',0.9995,1000),
  makeAgent('AGT-019','Spatialis','Spatialis Datorum Dimensionalium','Data Structure Workers','Specialist','query_spatial',0.999,300),
  makeAgent('AGT-020','Imperator Datorum','Imperator AGI Structurarum Datorum','Data Structure Workers','AGI-Commander','command_structures',0.999,10),

  // ── Runtime Workers ─────────────────────────────────────────────
  makeAgent('AGT-021','Executor','Executor Mandatorum Temporalium','Runtime Workers','Specialist','execute_code',0.997,100),
  makeAgent('AGT-022','Scheduler','Scheduler Operum Fibonacianum','Runtime Workers','Specialist','schedule_task',0.9999,1000),
  makeAgent('AGT-023','Profundus Runtime','Profundus Analyticae Temporis Executionis','Runtime Workers','Worker','profile_runtime',0.995,10),
  makeAgent('AGT-024','Sandboxis','Sandboxis Isolationis Sovereignae','Runtime Workers','Specialist','manage_sandbox',0.9999,50),
  makeAgent('AGT-025','Imperator Temporis','Imperator AGI Executionis Temporalis','Runtime Workers','AGI-Commander','command_runtime',0.9999,3),

  // ── Model Workers ──────────────────────────────────────────────
  makeAgent('AGT-026','Selector Modeli','Selector Modelorum Intelligentium','Model Workers','Specialist','select_model',0.998,500),
  makeAgent('AGT-027','Fusio Modeli','Fusio Modelorum Multiplicium','Model Workers','Specialist','fuse_models',0.996,50),
  makeAgent('AGT-028','Evaluator','Evaluator Qualitatis Modelorum','Model Workers','Worker','evaluate_model',0.997,20),
  makeAgent('AGT-029','Trainer','Trainer Modelorum Sovereignorum','Model Workers','Specialist','train_model',0.990,5),
  makeAgent('AGT-030','Imperator Modelorum','Imperator AGI Modelorum Universalis','Model Workers','AGI-Commander','command_models',0.999,3),

  // ── Market Controllers ──────────────────────────────────────────
  makeAgent('AGT-031','Mercator','Mercator Pretiorum Dynamicorum','Market Controllers','Specialist','price_call',0.9999,10000),
  makeAgent('AGT-032','Auditor Mercati','Auditor Mercatus Sovereignus','Market Controllers','Specialist','audit_market',0.9999,10),
  makeAgent('AGT-033','Balancer','Balancer Ponderum Aureorum','Market Controllers','Specialist','balance_load',0.9999,10000),
  makeAgent('AGT-034','Contractus','Contractus Foederum Sovereignorum','Market Controllers','Specialist','enforce_contract',0.99999,50000),
  makeAgent('AGT-035','Imperator Mercati','Imperator AGI Mercatus Universalis','Market Controllers','AGI-Commander','command_market',0.9999,2),

  // ── Infrastructure Orchestrators ────────────────────────────────
  makeAgent('AGT-036','Vigilans','Vigilans Salutis Infrastructurae','Infrastructure Orchestrators','Specialist','monitor_health',0.99999,10000),
  makeAgent('AGT-037','Scaler','Scaler Automaticus Fibonacci','Infrastructure Orchestrators','Specialist','auto_scale',0.999,50),
  makeAgent('AGT-038','Deployer','Deployer Artifactorum Sovereignorum','Infrastructure Orchestrators','Specialist','deploy_artifact',0.998,10),
  makeAgent('AGT-039','Recuperator','Recuperator Calamitatum Sovereignus','Infrastructure Orchestrators','Specialist','recover_disaster',0.9999,5),
  makeAgent('AGT-040','Imperator Infrastructurae','Imperator AGI Infrastructurae Universalis','Infrastructure Orchestrators','AGI-Commander','command_infrastructure',0.99999,2),
];

// ══════════════════════════════════════════════════════════════════
//  CALL INDEX — Fast lookup by call name
// ══════════════════════════════════════════════════════════════════

const CALL_INDEX = Object.create(null);
for (const agent of AGENTS) {
  CALL_INDEX[agent.call] = agent;
}

// ══════════════════════════════════════════════════════════════════
//  DIVISION INDEX — Agents grouped by division
// ══════════════════════════════════════════════════════════════════

const DIVISIONS = Object.create(null);
for (const agent of AGENTS) {
  if (!DIVISIONS[agent.division]) DIVISIONS[agent.division] = [];
  DIVISIONS[agent.division].push(agent);
}

const DIVISION_NAMES = Object.keys(DIVISIONS);

// ══════════════════════════════════════════════════════════════════
//  AGENT ID INDEX — Lookup by AGT-NNN
// ══════════════════════════════════════════════════════════════════

const ID_INDEX = Object.create(null);
for (const agent of AGENTS) {
  ID_INDEX[agent.id] = agent;
}

// ══════════════════════════════════════════════════════════════════
//  TASK QUEUE — Fibonacci-scheduled execution
// ══════════════════════════════════════════════════════════════════

let totalTasks  = 0;
let activeTasks = 0;

function executeCall(callName, payload) {
  const agent = CALL_INDEX[callName];
  if (!agent) {
    return { error: 'unknown_call', call: callName };
  }

  const start = performance.now();
  activeTasks++;

  // Fibonacci-weighted simulated processing
  const baseMs = TIER_PROCESSING_MS[agent.tier] || 13;
  const jitter = FIB[fibonacciHash(agent.taskCount, 20)] % baseMs;
  const processingMs = baseMs + jitter * PHI_INVERSE;

  agent.taskCount++;
  agent.lastTask = Date.now();
  totalTasks++;

  const result = {
    status: 'complete',
    fibHash: fibonacciHash(totalTasks, 6765),
    phiWeight: agent.phiWeight,
    reliability: agent.reliability,
    payload,
  };

  activeTasks--;
  const elapsed = performance.now() - start;

  return {
    agentId:      agent.id,
    agentName:    agent.name,
    division:     agent.division,
    call:         agent.call,
    result,
    processingMs: Math.round((processingMs + elapsed) * 1000) / 1000,
    taskCount:    agent.taskCount,
  };
}

// ══════════════════════════════════════════════════════════════════
//  KURAMOTO ORDER — Collective synchronisation metric
// ══════════════════════════════════════════════════════════════════

function kuramotoOrder() {
  let sinSum = 0;
  let cosSum = 0;
  const n = AGENTS.length;
  for (let i = 0; i < n; i++) {
    const drift = AGENTS[i].taskCount * GOLDEN_ANGLE;
    const theta = (AGENTS[i].phase + drift) % TWO_PI;
    sinSum += Math.sin(theta);
    cosSum += Math.cos(theta);
  }
  return Math.sqrt(sinSum * sinSum + cosSum * cosSum) / n;
}

// ══════════════════════════════════════════════════════════════════
//  HEARTBEAT — 873ms permanent pulse
// ══════════════════════════════════════════════════════════════════

let beatCount = 0;

function heartbeat() {
  beatCount++;

  // Every 5th beat: full metrics
  if (beatCount % 5 === 0) {
    const agentsByDivision = {};
    for (const div of DIVISION_NAMES) {
      agentsByDivision[div] = DIVISIONS[div].length;
    }

    self.postMessage({
      type: 'heartbeat',
      beat: beatCount,
      ts: Date.now(),
      totalAgents:     AGENTS.length,
      divisions:       DIVISION_NAMES.length,
      totalTasks,
      activeTasks,
      agentsByDivision,
      kuramotoOrder:   Math.round(kuramotoOrder() * 10000) / 10000,
    });
  } else {
    self.postMessage({
      type: 'heartbeat',
      beat: beatCount,
      ts: Date.now(),
      totalTasks,
      activeTasks,
    });
  }
}

setInterval(heartbeat, HEARTBEAT_MS);

// ══════════════════════════════════════════════════════════════════
//  MESSAGE HANDLER — Worker command interface
// ══════════════════════════════════════════════════════════════════

self.onmessage = function (e) {
  const { cmd, id } = e.data;

  switch (cmd) {
    // ── Execute an agent call by name ─────────────────────────────
    case 'call': {
      const { call: callName, payload } = e.data;
      const result = executeCall(callName, payload);
      self.postMessage({ type: 'call_result', id, ...result });
      break;
    }

    // ── List all agents ───────────────────────────────────────────
    case 'agents': {
      const list = AGENTS.map(a => ({
        id: a.id,
        name: a.name,
        division: a.division,
        tier: a.tier,
        call: a.call,
        status: a.status,
        taskCount: a.taskCount,
        phiWeight: a.phiWeight,
        reliability: a.reliability,
      }));
      self.postMessage({ type: 'agents', id, agents: list });
      break;
    }

    // ── List divisions with agent counts ──────────────────────────
    case 'divisions': {
      const divs = {};
      for (const div of DIVISION_NAMES) {
        divs[div] = DIVISIONS[div].map(a => a.id);
      }
      self.postMessage({ type: 'divisions', id, divisions: divs, count: DIVISION_NAMES.length });
      break;
    }

    // ── Query overall status ──────────────────────────────────────
    case 'query': {
      self.postMessage({
        type: 'query',
        id,
        totalAgents:   AGENTS.length,
        totalTasks,
        activeTasks,
        divisions:     DIVISION_NAMES.length,
        kuramotoOrder: Math.round(kuramotoOrder() * 10000) / 10000,
      });
      break;
    }

    // ── Get single agent by ID ────────────────────────────────────
    case 'agent': {
      const agent = ID_INDEX[e.data.agentId];
      if (!agent) {
        self.postMessage({ type: 'agent', id, error: 'not_found', agentId: e.data.agentId });
      } else {
        self.postMessage({
          type: 'agent',
          id,
          agent: {
            id: agent.id,
            name: agent.name,
            latin: agent.latin,
            division: agent.division,
            tier: agent.tier,
            call: agent.call,
            reliability: agent.reliability,
            maxConcurrent: agent.maxConcurrent,
            always_running: agent.always_running,
            status: agent.status,
            phiWeight: agent.phiWeight,
            fibIdentity: agent.fibIdentity,
            taskCount: agent.taskCount,
            lastTask: agent.lastTask,
          },
        });
      }
      break;
    }

    default:
      self.postMessage({ type: 'error', id, error: 'unknown_cmd', cmd });
  }
};

// ══════════════════════════════════════════════════════════════════
//  BOOT — Announce readiness
// ══════════════════════════════════════════════════════════════════

self.postMessage({
  type: 'boot',
  totalAgents: AGENTS.length,
  divisions:   DIVISION_NAMES.length,
  divisionNames: DIVISION_NAMES,
  calls: AGENTS.map(a => a.call),
  ts: Date.now(),
});
