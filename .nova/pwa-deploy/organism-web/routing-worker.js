///
/// NOVA ROUTING WORKER — Intelligence Wire Routing Brain
///
/// A permanent Web Worker that routes tasks to optimal AI engines
/// using φ-weighted scoring across 40 foundation model families.
/// Adaptive success tracking, multi-route batching, ring-affinity
/// bonuses. 873ms heartbeat. Zero dependencies.
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
//  CAPABILITIES & RINGS
// ═══════════════════════════════════════════════════════════════

const CAPABILITIES = [
  'reasoning','code-generation','vision','audio','image-generation',
  'video-generation','music-generation','search','embedding','safety',
  'math','multilingual','voice-synthesis','robotics'
];

const RINGS = [
  'Interface Ring','Memory Ring','Geometry Ring','Transport Ring',
  'Build Ring','Proof Ring','Sovereign Ring','Counsel Ring',
  'Native Capability Ring'
];

// ═══════════════════════════════════════════════════════════════
//  ROUTING TABLE — 40 AI Foundation Engines
// ═══════════════════════════════════════════════════════════════

var ROUTING_TABLE = [
  { id:'AIF-001', family:'GPT',               ring:'Interface Ring',          priority:0, capabilities:['reasoning','code-generation','vision','audio'],              phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
  { id:'AIF-002', family:'Claude',             ring:'Interface Ring',          priority:0, capabilities:['reasoning','code-generation','vision','safety'],             phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
  { id:'AIF-003', family:'Gemini',             ring:'Interface Ring',          priority:0, capabilities:['reasoning','code-generation','vision','audio'],              phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
  { id:'AIF-004', family:'Llama',              ring:'Sovereign Ring',          priority:1, capabilities:['reasoning','code-generation','multilingual'],                phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-005', family:'Mistral',            ring:'Interface Ring',          priority:1, capabilities:['reasoning','code-generation','multilingual'],                phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-006', family:'Command R',          ring:'Memory Ring',            priority:1, capabilities:['reasoning','search','multilingual'],                         phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-007', family:'Phi',                ring:'Sovereign Ring',          priority:2, capabilities:['reasoning','code-generation','math'],                       phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-008', family:'Gemma',              ring:'Sovereign Ring',          priority:2, capabilities:['reasoning','code-generation','safety'],                     phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-009', family:'Qwen',               ring:'Interface Ring',          priority:2, capabilities:['reasoning','code-generation','math','multilingual'],        phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-010', family:'DBRX',               ring:'Build Ring',             priority:2, capabilities:['reasoning','code-generation'],                              phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-011', family:'Falcon',             ring:'Sovereign Ring',          priority:3, capabilities:['reasoning','multilingual'],                                 phiWeight:Math.pow(PHI,1), successRate:1.0, routeCount:0 },
  { id:'AIF-012', family:'Yi',                 ring:'Interface Ring',          priority:3, capabilities:['reasoning','code-generation','math','multilingual'],        phiWeight:Math.pow(PHI,1), successRate:1.0, routeCount:0 },
  { id:'AIF-013', family:'Stable Diffusion',   ring:'Geometry Ring',           priority:1, capabilities:['image-generation'],                                        phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-014', family:'DALL-E',             ring:'Geometry Ring',           priority:1, capabilities:['image-generation'],                                        phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-015', family:'Midjourney',         ring:'Geometry Ring',           priority:2, capabilities:['image-generation'],                                        phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-016', family:'Whisper',            ring:'Native Capability Ring',  priority:1, capabilities:['audio','multilingual'],                                    phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-017', family:'ElevenLabs',         ring:'Native Capability Ring',  priority:1, capabilities:['voice-synthesis','audio'],                                 phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-018', family:'Suno',               ring:'Geometry Ring',           priority:2, capabilities:['music-generation','audio'],                                phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-019', family:'Codex / Copilot',    ring:'Build Ring',             priority:0, capabilities:['code-generation','reasoning'],                              phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
  { id:'AIF-020', family:'CodeLlama',          ring:'Build Ring',             priority:2, capabilities:['code-generation'],                                          phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-021', family:'DeepSeek',           ring:'Build Ring',             priority:2, capabilities:['code-generation','math','reasoning'],                       phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-022', family:'Perplexity',         ring:'Transport Ring',          priority:1, capabilities:['search','reasoning'],                                      phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-023', family:'Grok',               ring:'Transport Ring',          priority:2, capabilities:['search','reasoning'],                                      phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-024', family:'Inflection',         ring:'Memory Ring',            priority:2, capabilities:['reasoning'],                                                phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-025', family:'Jamba',              ring:'Memory Ring',            priority:2, capabilities:['reasoning'],                                                phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-026', family:'Sora',               ring:'Geometry Ring',           priority:1, capabilities:['video-generation'],                                        phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-027', family:'Runway',             ring:'Geometry Ring',           priority:2, capabilities:['video-generation'],                                        phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-028', family:'Pika',               ring:'Geometry Ring',           priority:3, capabilities:['video-generation'],                                        phiWeight:Math.pow(PHI,1), successRate:1.0, routeCount:0 },
  { id:'AIF-029', family:'Kling',              ring:'Geometry Ring',           priority:3, capabilities:['video-generation'],                                        phiWeight:Math.pow(PHI,1), successRate:1.0, routeCount:0 },
  { id:'AIF-030', family:'AlphaFold',          ring:'Proof Ring',             priority:1, capabilities:['reasoning'],                                                phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-031', family:'AlphaCode',          ring:'Proof Ring',             priority:2, capabilities:['code-generation','math'],                                   phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-032', family:'RT-2',               ring:'Sovereign Ring',          priority:2, capabilities:['robotics','vision'],                                       phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-033', family:'Segment Anything',   ring:'Geometry Ring',           priority:1, capabilities:['vision'],                                                  phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-034', family:'CLIP',               ring:'Memory Ring',            priority:1, capabilities:['vision','embedding'],                                      phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-035', family:'Florence',           ring:'Geometry Ring',           priority:2, capabilities:['vision'],                                                  phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-036', family:'Minerva / Llemma',   ring:'Proof Ring',             priority:2, capabilities:['math','reasoning'],                                        phiWeight:Math.pow(PHI,2), successRate:1.0, routeCount:0 },
  { id:'AIF-037', family:'MusicLM / MusicGen', ring:'Geometry Ring',           priority:3, capabilities:['music-generation'],                                        phiWeight:Math.pow(PHI,1), successRate:1.0, routeCount:0 },
  { id:'AIF-038', family:'Embedding Models',   ring:'Memory Ring',            priority:0, capabilities:['embedding'],                                               phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
  { id:'AIF-039', family:'Reranking Models',   ring:'Memory Ring',            priority:1, capabilities:['search','embedding'],                                      phiWeight:Math.pow(PHI,3), successRate:1.0, routeCount:0 },
  { id:'AIF-040', family:'Guard Models',       ring:'Counsel Ring',           priority:0, capabilities:['safety'],                                                  phiWeight:Math.pow(PHI,4), successRate:1.0, routeCount:0 },
];

// ═══════════════════════════════════════════════════════════════
//  ROUTING LOGIC — φ-weighted scoring
// ═══════════════════════════════════════════════════════════════

var totalRoutes = 0;
var scoreAccum  = 0;

function routeTask(capability, preferredRing) {
  totalRoutes++;
  var candidates = [];

  for (var i = 0; i < ROUTING_TABLE.length; i++) {
    var eng = ROUTING_TABLE[i];
    if (eng.capabilities.indexOf(capability) === -1) continue;

    var coverage  = eng.capabilities.length / CAPABILITIES.length;
    var ringBonus = (preferredRing && eng.ring === preferredRing) ? PHI : 1.0;
    var costFactor = eng.priority * PHI_INVERSE * 0.1;
    var score = (coverage * eng.phiWeight * ringBonus) - costFactor + eng.successRate * PHI;

    candidates.push({ id: eng.id, family: eng.family, ring: eng.ring, score: Math.round(score * 10000) / 10000 });
  }

  candidates.sort(function(a, b) { return b.score - a.score; });

  if (candidates.length === 0) {
    return { selected: null, alternatives: [], routed: false };
  }

  var selected = candidates[0];
  for (var j = 0; j < ROUTING_TABLE.length; j++) {
    if (ROUTING_TABLE[j].id === selected.id) {
      ROUTING_TABLE[j].routeCount++;
      break;
    }
  }

  scoreAccum += selected.score;

  return {
    selected:     selected,
    alternatives: candidates.slice(1, 4),
    routed:       true,
  };
}

// ═══════════════════════════════════════════════════════════════
//  MULTI-ROUTE — batch routing
// ═══════════════════════════════════════════════════════════════

function multiRoute(tasks) {
  var results = [];
  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i];
    results.push(routeTask(t.capability, t.preferredRing));
  }
  return results;
}

// ═══════════════════════════════════════════════════════════════
//  ADAPTIVE UPDATE — exponential moving average
// ═══════════════════════════════════════════════════════════════

function adaptiveUpdate(engineId, success) {
  for (var i = 0; i < ROUTING_TABLE.length; i++) {
    if (ROUTING_TABLE[i].id === engineId) {
      var alpha = PHI_INVERSE;
      var val   = success ? 1.0 : 0.0;
      ROUTING_TABLE[i].successRate = alpha * val + (1 - alpha) * ROUTING_TABLE[i].successRate;
      return {
        engineId:    engineId,
        successRate: Math.round(ROUTING_TABLE[i].successRate * 10000) / 10000,
        updated:     true,
      };
    }
  }
  return { engineId: engineId, updated: false, error: 'engine not found' };
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
    worker: 'routing-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';
    msg.metrics = {
      totalRoutes: totalRoutes,
      avgScore:    totalRoutes > 0 ? Math.round((scoreAccum / totalRoutes) * 10000) / 10000 : 0,
      topEngines:  ROUTING_TABLE.slice().sort(function(a,b) { return b.routeCount - a.routeCount; }).slice(0,5).map(function(e) { return { id:e.id, family:e.family, routes:e.routeCount }; }),
      uptimeMs:    Date.now() - startMs,
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
    // ── route — route a single task ────────────────────────
    case 'route': {
      result = { ok: true, route: routeTask(msg.capability, msg.preferredRing) };
      break;
    }

    // ── multi_route — batch route ──────────────────────────
    case 'multi_route': {
      result = { ok: true, routes: multiRoute(msg.tasks || []) };
      break;
    }

    // ── update — adaptive success update ───────────────────
    case 'update': {
      result = { ok: true, update: adaptiveUpdate(msg.engineId, msg.success) };
      break;
    }

    // ── table — dump full routing table ────────────────────
    case 'table': {
      var table = ROUTING_TABLE.map(function(e) {
        return { id:e.id, family:e.family, ring:e.ring, priority:e.priority, successRate:Math.round(e.successRate*10000)/10000, routeCount:e.routeCount, capabilities:e.capabilities };
      });
      result = { ok: true, table: table, count: table.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:          true,
        engines:     ROUTING_TABLE.length,
        capabilities: CAPABILITIES.length,
        rings:       RINGS.length,
        totalRoutes: totalRoutes,
        avgScore:    totalRoutes > 0 ? Math.round((scoreAccum / totalRoutes) * 10000) / 10000 : 0,
        uptime:      beatCount * HEARTBEAT_MS,
        heartbeatMs: HEARTBEAT_MS,
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
  worker:       'routing-worker',
  engines:      ROUTING_TABLE.length,
  capabilities: CAPABILITIES.length,
  rings:        RINGS.length,
  heartbeatMs:  HEARTBEAT_MS,
  phi:          PHI,
  ts:           Date.now(),
});
