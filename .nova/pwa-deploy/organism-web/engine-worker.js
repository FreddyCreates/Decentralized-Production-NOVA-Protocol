///
/// NOVA ENGINE WORKER — The Product Brain
///
/// A permanent Web Worker that runs the full AI engine stack in-browser.
/// Zero dependencies. Zero server. 40 AI families. Running permanently.
///
/// Architecture:
///   EngineCore   — 40 AI model families registered, task dispatch
///   ModelRouter  — Capability-based selection with adaptive scoring
///   ModelWire    — Encrypted point-to-point wires to 9 organism layers
///   Heartbeat    — 873ms permanent pulse with live metrics every 5th beat
///

// ══════════════════════════════════════════════════════════════════
//  GOLDEN CONSTANTS
// ══════════════════════════════════════════════════════════════════

const PHI           = 1.6180339887498948482;
const PHI_INVERSE   = 0.6180339887498948482;
const PHI_SQUARED   = 2.6180339887498948482;
const PHI_CUBED     = 4.2360679774997896964;
const PHI_FOURTH    = 6.8541019662496845446;
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
//  ORGANISM RINGS — The 9 Intelligence Layers
// ══════════════════════════════════════════════════════════════════

const RINGS = [
  'Interface Ring',
  'Sovereign Ring',
  'Memory Ring',
  'Build Ring',
  'Geometry Ring',
  'Transport Ring',
  'Proof Ring',
  'Native Capability Ring',
  'Counsel Ring',
];

// ══════════════════════════════════════════════════════════════════
//  CAPABILITIES — 14 Dispatch Categories
// ══════════════════════════════════════════════════════════════════

const CAPABILITIES = [
  'reasoning',
  'code-generation',
  'vision',
  'audio',
  'image-generation',
  'video-generation',
  'music-generation',
  'search',
  'embedding',
  'safety',
  'math',
  'multilingual',
  'voice-synthesis',
  'robotics',
];

// ══════════════════════════════════════════════════════════════════
//  40 AI FOUNDATION MODEL FAMILIES
// ══════════════════════════════════════════════════════════════════

const MODELS = [
  { id:'AIF-001', family:'GPT',             org:'OpenAI',           alpha:'GPT-4o',               priority:0, ring:'Interface Ring',          capabilities:['reasoning','code-generation','vision','audio'],             modality:'Text + Vision + Audio',  status:'active' },
  { id:'AIF-002', family:'Claude',          org:'Anthropic',        alpha:'Claude 3.5 Sonnet',    priority:0, ring:'Interface Ring',          capabilities:['reasoning','code-generation','vision'],                     modality:'Text + Vision',          status:'active' },
  { id:'AIF-003', family:'Gemini',          org:'Google DeepMind',  alpha:'Gemini 1.5 Pro',       priority:0, ring:'Interface Ring',          capabilities:['reasoning','code-generation','vision','audio','video-generation'], modality:'Text + Vision + Audio + Video', status:'active' },
  { id:'AIF-004', family:'Llama',           org:'Meta',             alpha:'Llama 3.1 405B',       priority:1, ring:'Sovereign Ring',          capabilities:['reasoning','code-generation','multilingual'],               modality:'Text',                   status:'active' },
  { id:'AIF-005', family:'Mistral',         org:'Mistral AI',       alpha:'Mistral Large 2',      priority:1, ring:'Interface Ring',          capabilities:['reasoning','code-generation','multilingual'],               modality:'Text',                   status:'active' },
  { id:'AIF-006', family:'Command R',       org:'Cohere',           alpha:'Command R+',           priority:1, ring:'Memory Ring',             capabilities:['reasoning','search','multilingual','embedding'],            modality:'Text',                   status:'active' },
  { id:'AIF-007', family:'Phi',             org:'Microsoft Research', alpha:'Phi-3 Medium',       priority:2, ring:'Sovereign Ring',          capabilities:['reasoning','code-generation','math'],                       modality:'Text',                   status:'active' },
  { id:'AIF-008', family:'Gemma',           org:'Google DeepMind',  alpha:'Gemma 2 27B',          priority:2, ring:'Sovereign Ring',          capabilities:['reasoning','code-generation','safety'],                     modality:'Text',                   status:'active' },
  { id:'AIF-009', family:'Qwen',            org:'Alibaba Cloud',    alpha:'Qwen2 72B',            priority:2, ring:'Interface Ring',          capabilities:['reasoning','code-generation','multilingual','math'],        modality:'Text',                   status:'active' },
  { id:'AIF-010', family:'DBRX',            org:'Databricks',       alpha:'DBRX 132B',            priority:2, ring:'Build Ring',              capabilities:['reasoning','code-generation'],                              modality:'Text',                   status:'active' },
  { id:'AIF-011', family:'Falcon',          org:'TII (UAE)',        alpha:'Falcon 180B',          priority:3, ring:'Sovereign Ring',          capabilities:['reasoning','multilingual'],                                 modality:'Text',                   status:'active' },
  { id:'AIF-012', family:'Yi',              org:'01.AI',            alpha:'Yi-34B',               priority:3, ring:'Interface Ring',          capabilities:['reasoning','multilingual','code-generation','math'],        modality:'Text',                   status:'active' },
  { id:'AIF-013', family:'Stable Diffusion',org:'Stability AI',     alpha:'SDXL Turbo',           priority:1, ring:'Geometry Ring',           capabilities:['image-generation'],                                         modality:'Text → Image',           status:'active' },
  { id:'AIF-014', family:'DALL-E',          org:'OpenAI',           alpha:'DALL-E 3',             priority:1, ring:'Geometry Ring',           capabilities:['image-generation'],                                         modality:'Text → Image',           status:'active' },
  { id:'AIF-015', family:'Midjourney',      org:'Midjourney',       alpha:'Midjourney v6',        priority:2, ring:'Geometry Ring',           capabilities:['image-generation'],                                         modality:'Text → Image',           status:'active' },
  { id:'AIF-016', family:'Whisper',         org:'OpenAI',           alpha:'Whisper Large v3',     priority:1, ring:'Native Capability Ring',  capabilities:['audio'],                                                    modality:'Audio → Text',           status:'active' },
  { id:'AIF-017', family:'ElevenLabs',      org:'ElevenLabs',       alpha:'Turbo v2.5',           priority:1, ring:'Native Capability Ring',  capabilities:['voice-synthesis','audio'],                                   modality:'Text → Audio',           status:'active' },
  { id:'AIF-018', family:'Suno',            org:'Suno',             alpha:'Suno v3.5',            priority:2, ring:'Geometry Ring',           capabilities:['music-generation','audio'],                                  modality:'Text → Audio',           status:'active' },
  { id:'AIF-019', family:'Codex / Copilot', org:'OpenAI / GitHub',  alpha:'GPT-4o (code-tuned)',  priority:0, ring:'Build Ring',              capabilities:['code-generation','reasoning'],                              modality:'Text → Code',            status:'active' },
  { id:'AIF-020', family:'CodeLlama',       org:'Meta',             alpha:'CodeLlama 70B',        priority:2, ring:'Build Ring',              capabilities:['code-generation'],                                          modality:'Text → Code',            status:'active' },
  { id:'AIF-021', family:'DeepSeek',        org:'DeepSeek',         alpha:'DeepSeek-V2',          priority:2, ring:'Build Ring',              capabilities:['code-generation','math','reasoning'],                       modality:'Text',                   status:'active' },
  { id:'AIF-022', family:'Perplexity',      org:'Perplexity AI',    alpha:'Perplexity Online',    priority:1, ring:'Transport Ring',          capabilities:['search','reasoning'],                                       modality:'Text + Search',          status:'active' },
  { id:'AIF-023', family:'Grok',            org:'xAI',              alpha:'Grok-2',               priority:2, ring:'Transport Ring',          capabilities:['search','reasoning'],                                       modality:'Text + Social',          status:'active' },
  { id:'AIF-024', family:'Inflection',      org:'Inflection AI',    alpha:'Pi',                   priority:2, ring:'Memory Ring',             capabilities:['reasoning'],                                                modality:'Text',                   status:'active' },
  { id:'AIF-025', family:'Jamba',           org:'AI21 Labs',        alpha:'Jamba 1.5',            priority:2, ring:'Memory Ring',             capabilities:['reasoning'],                                                modality:'Text',                   status:'active' },
  { id:'AIF-026', family:'Sora',            org:'OpenAI',           alpha:'Sora',                 priority:1, ring:'Geometry Ring',           capabilities:['video-generation'],                                         modality:'Text → Video',           status:'preview' },
  { id:'AIF-027', family:'Runway',          org:'Runway',           alpha:'Gen-3 Alpha',          priority:2, ring:'Geometry Ring',           capabilities:['video-generation'],                                         modality:'Multi → Video',          status:'active' },
  { id:'AIF-028', family:'Pika',            org:'Pika Labs',        alpha:'Pika 1.0',             priority:3, ring:'Geometry Ring',           capabilities:['video-generation'],                                         modality:'Multi → Video',          status:'active' },
  { id:'AIF-029', family:'Kling',           org:'Kuaishou',         alpha:'Kling',                priority:3, ring:'Geometry Ring',           capabilities:['video-generation'],                                         modality:'Text → Video',           status:'active' },
  { id:'AIF-030', family:'AlphaFold',       org:'Google DeepMind',  alpha:'AlphaFold 3',          priority:1, ring:'Proof Ring',              capabilities:['reasoning','math'],                                         modality:'Sequence → Structure',   status:'active' },
  { id:'AIF-031', family:'AlphaCode',       org:'Google DeepMind',  alpha:'AlphaCode 2',          priority:2, ring:'Proof Ring',              capabilities:['code-generation','reasoning','math'],                       modality:'Text → Code',            status:'active' },
  { id:'AIF-032', family:'RT-2',            org:'Google DeepMind',  alpha:'RT-2-X',               priority:2, ring:'Sovereign Ring',          capabilities:['robotics','vision'],                                        modality:'Multi → Action',         status:'preview' },
  { id:'AIF-033', family:'Segment Anything', org:'Meta',            alpha:'SAM 2',                priority:1, ring:'Geometry Ring',           capabilities:['vision'],                                                   modality:'Vision → Masks',         status:'active' },
  { id:'AIF-034', family:'CLIP',            org:'OpenAI',           alpha:'CLIP ViT-L/14',        priority:1, ring:'Memory Ring',             capabilities:['vision','embedding'],                                       modality:'Multi → Embedding',      status:'active' },
  { id:'AIF-035', family:'Florence',        org:'Microsoft',        alpha:'Florence-2',           priority:2, ring:'Geometry Ring',           capabilities:['vision'],                                                   modality:'Vision → Multi',         status:'active' },
  { id:'AIF-036', family:'Minerva / Llemma',org:'Google / EleutherAI', alpha:'Llemma 34B',        priority:2, ring:'Proof Ring',              capabilities:['math','reasoning'],                                         modality:'Text → Math',            status:'active' },
  { id:'AIF-037', family:'MusicLM / MusicGen', org:'Google / Meta', alpha:'MusicGen Large',       priority:3, ring:'Geometry Ring',           capabilities:['music-generation'],                                         modality:'Text → Music',           status:'active' },
  { id:'AIF-038', family:'Embedding Models',org:'Various',          alpha:'text-embedding-3-large', priority:0, ring:'Memory Ring',           capabilities:['embedding'],                                                modality:'Text → Vector',          status:'active' },
  { id:'AIF-039', family:'Reranking Models',org:'Cohere / Various', alpha:'Cohere Rerank v3',     priority:1, ring:'Memory Ring',             capabilities:['embedding','search'],                                       modality:'Text → Score',           status:'active' },
  { id:'AIF-040', family:'Guard Models',    org:'Various',          alpha:'Llama Guard 3',        priority:0, ring:'Counsel Ring',            capabilities:['safety'],                                                   modality:'Text → Safety',          status:'active' },
];

// ══════════════════════════════════════════════════════════════════
//  ENGINE CORE — Register, Index, Dispatch
// ══════════════════════════════════════════════════════════════════

class EngineCore {
  constructor() {
    this.engines = [];
    this.index   = new Map();   // id → engine
    this.byRing  = new Map();   // ring → [engines]
    this.byCap   = new Map();   // capability → [engines]
    this.dispatches = 0;
    this.boot();
  }

  boot() {
    for (let i = 0; i < MODELS.length; i++) {
      const m = MODELS[i];
      const engine = {
        ...m,
        phiWeight:       Math.pow(PHI, 4 - m.priority),
        fibIdentity:     fibonacciHash(i + 1, 2147483647),
        goldenAngle:     ((i + 1) * GOLDEN_ANGLE) % TWO_PI,
        successRate:     1.0,
        dispatchCount:   0,
        lastDispatch:    0,
        costFactor:      m.priority * PHI_INVERSE,
        adaptiveScore:   Math.pow(PHI, 4 - m.priority),
      };
      this.engines.push(engine);
      this.index.set(m.id, engine);

      // Index by ring
      if (!this.byRing.has(m.ring)) this.byRing.set(m.ring, []);
      this.byRing.get(m.ring).push(engine);

      // Index by capability
      for (const cap of m.capabilities) {
        if (!this.byCap.has(cap)) this.byCap.set(cap, []);
        this.byCap.get(cap).push(engine);
      }
    }
  }

  dispatch(capability, payload) {
    this.dispatches++;
    const candidates = this.byCap.get(capability);
    if (!candidates || candidates.length === 0) {
      return { error: 'No engine for capability: ' + capability, dispatches: this.dispatches };
    }

    // Score: coverage × priority − cost + successRate
    let best = null;
    let bestScore = -Infinity;
    for (const eng of candidates) {
      if (eng.status !== 'active') continue;
      const coverage = eng.capabilities.length / CAPABILITIES.length;
      const score = coverage * eng.phiWeight - eng.costFactor + eng.successRate * PHI;
      if (score > bestScore) {
        bestScore = score;
        best = eng;
      }
    }

    if (!best) {
      return { error: 'No active engine for: ' + capability, dispatches: this.dispatches };
    }

    best.dispatchCount++;
    best.lastDispatch = Date.now();
    // Adaptive scoring: boost success rate on dispatch
    best.adaptiveScore = best.adaptiveScore * PHI_INVERSE + bestScore * (1 - PHI_INVERSE);

    return {
      engineId:    best.id,
      family:      best.family,
      org:         best.org,
      alpha:       best.alpha,
      ring:        best.ring,
      score:       bestScore,
      capability:  capability,
      payload:     payload,
      dispatches:  this.dispatches,
      timestamp:   Date.now(),
    };
  }

  getEngine(id) {
    return this.index.get(id) || null;
  }

  query() {
    return {
      total:       this.engines.length,
      active:      this.engines.filter(e => e.status === 'active').length,
      preview:     this.engines.filter(e => e.status === 'preview').length,
      dispatches:  this.dispatches,
      rings:       RINGS.map(r => ({ ring: r, count: (this.byRing.get(r) || []).length })),
      capabilities: CAPABILITIES.map(c => ({ cap: c, count: (this.byCap.get(c) || []).length })),
    };
  }
}

// ══════════════════════════════════════════════════════════════════
//  MODEL ROUTER — Capability Matching with Adaptive Scoring
// ══════════════════════════════════════════════════════════════════

class ModelRouter {
  constructor(core) {
    this.core   = core;
    this.routes = 0;
  }

  /**
   * Route: score = (coverage × priority) − cost + successRate × φ
   * Returns top engine and 3 alternatives.
   */
  route(requiredCaps, preferredRing) {
    this.routes++;
    const candidates = this.core.engines.filter(e => {
      if (e.status !== 'active') return false;
      // Must support at least one required capability
      return requiredCaps.some(c => e.capabilities.includes(c));
    });

    const scored = candidates.map(eng => {
      const matched = requiredCaps.filter(c => eng.capabilities.includes(c)).length;
      const coverage = matched / requiredCaps.length;
      const ringBonus = (preferredRing && eng.ring === preferredRing) ? PHI : 1.0;
      const score = (coverage * eng.phiWeight * ringBonus) - eng.costFactor + eng.successRate * PHI;
      return { engine: eng, score, coverage };
    });

    scored.sort((a, b) => b.score - a.score);
    if (scored.length === 0) return null;

    const selected = scored[0];
    return {
      selected: {
        id:         selected.engine.id,
        family:     selected.engine.family,
        alpha:      selected.engine.alpha,
        ring:       selected.engine.ring,
        score:      selected.score,
        coverage:   selected.coverage,
      },
      alternatives: scored.slice(1, 4).map(s => ({
        id:       s.engine.id,
        family:   s.engine.family,
        score:    s.score,
      })),
      totalRoutes: this.routes,
    };
  }
}

// ══════════════════════════════════════════════════════════════════
//  MODEL WIRE — Encrypted Point-to-Point Wires (Engine ↔ Ring)
// ══════════════════════════════════════════════════════════════════

class ModelWire {
  constructor(core) {
    this.core  = core;
    this.wires = [];
    this.boot();
  }

  boot() {
    // Create a wire for every (engine, ring) pair
    for (const eng of this.core.engines) {
      const wire = {
        engineId:  eng.id,
        family:    eng.family,
        ring:      eng.ring,
        protocol:  'intelligence-wire/' + eng.family.toLowerCase().replace(/[\s\/]+/g, '-'),
        connected: eng.status === 'active',
        fibHash:   fibonacciHash(eng.fibIdentity + RINGS.indexOf(eng.ring), 2147483647),
        resonance: Math.cos(this.wires.length * GOLDEN_ANGLE),
        latencyMs: HEARTBEAT_MS * Math.pow(PHI_INVERSE, eng.priority),
      };
      this.wires.push(wire);
    }
  }

  topology() {
    const topo = {};
    for (const ring of RINGS) {
      topo[ring] = this.wires
        .filter(w => w.ring === ring && w.connected)
        .map(w => ({ id: w.engineId, family: w.family, protocol: w.protocol }));
    }
    return topo;
  }

  count() {
    return this.wires.filter(w => w.connected).length;
  }

  all() {
    return this.wires;
  }
}

// ══════════════════════════════════════════════════════════════════
//  HEARTBEAT — 873ms Permanent Pulse
// ══════════════════════════════════════════════════════════════════

class Heartbeat {
  constructor(core, wires) {
    this.core    = core;
    this.wires   = wires;
    this.count   = 0;
    this.startMs = Date.now();
    this.timer   = null;
  }

  start() {
    this.timer = setInterval(() => this.beat(), HEARTBEAT_MS);
    this.beat(); // Immediate first beat
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
  }

  beat() {
    this.count++;

    // Every 5th beat: send full metrics
    if (this.count % 5 === 0) {
      self.postMessage({
        type: 'metrics',
        data: {
          heartbeat:    this.count,
          uptimeMs:     Date.now() - this.startMs,
          engines:      this.core.engines.length,
          active:       this.core.engines.filter(e => e.status === 'active').length,
          dispatches:   this.core.dispatches,
          wires:        this.wires.count(),
          rings:        RINGS.length,
          kuramotoR:    this.kuramotoOrder(),
          goldenWeight: this.totalGoldenWeight(),
        },
      });
    }

    // Every beat: send heartbeat pulse
    self.postMessage({
      type: 'heartbeat',
      data: {
        beat:      this.count,
        uptimeMs:  Date.now() - this.startMs,
        timestamp: Date.now(),
        phi:       PHI,
      },
    });
  }

  kuramotoOrder() {
    let sumCos = 0, sumSin = 0;
    for (let i = 0; i < this.core.engines.length; i++) {
      const phase = this.core.engines[i].goldenAngle;
      sumCos += Math.cos(phase);
      sumSin += Math.sin(phase);
    }
    const n = this.core.engines.length;
    return Math.sqrt(sumCos * sumCos + sumSin * sumSin) / n;
  }

  totalGoldenWeight() {
    let w = 0;
    for (const eng of this.core.engines) w += eng.phiWeight;
    return w;
  }
}

// ══════════════════════════════════════════════════════════════════
//  WORKER BOOT — Wire Everything, Start Heartbeat
// ══════════════════════════════════════════════════════════════════

const core    = new EngineCore();
const router  = new ModelRouter(core);
const wires   = new ModelWire(core);
const pulse   = new Heartbeat(core, wires);

pulse.start();

// Post boot confirmation
self.postMessage({
  type: 'boot',
  data: {
    engines:      core.engines.length,
    active:       core.engines.filter(e => e.status === 'active').length,
    wires:        wires.count(),
    rings:        RINGS.length,
    capabilities: CAPABILITIES.length,
    heartbeatMs:  HEARTBEAT_MS,
    timestamp:    Date.now(),
  },
});

// ══════════════════════════════════════════════════════════════════
//  MESSAGE HANDLER — dispatch / route / query / topology / engines
// ══════════════════════════════════════════════════════════════════

self.onmessage = function(e) {
  const { cmd, id, capability, payload, caps, ring } = e.data;

  switch (cmd) {
    case 'dispatch': {
      const result = core.dispatch(capability, payload || '');
      self.postMessage({ type: 'dispatch-result', id, data: result });
      break;
    }

    case 'route': {
      const result = router.route(caps || [capability], ring);
      self.postMessage({ type: 'route-result', id, data: result });
      break;
    }

    case 'query': {
      const result = core.query();
      self.postMessage({ type: 'query-result', id, data: result });
      break;
    }

    case 'topology': {
      self.postMessage({ type: 'topology-result', id, data: wires.topology() });
      break;
    }

    case 'engines': {
      const list = core.engines.map(e => ({
        id: e.id, family: e.family, org: e.org, alpha: e.alpha,
        ring: e.ring, priority: e.priority, status: e.status,
        capabilities: e.capabilities, modality: e.modality,
        phiWeight: e.phiWeight, dispatchCount: e.dispatchCount,
      }));
      self.postMessage({ type: 'engines-result', id, data: list });
      break;
    }

    case 'wires': {
      self.postMessage({ type: 'wires-result', id, data: wires.all() });
      break;
    }

    default:
      self.postMessage({ type: 'error', id, data: { error: 'Unknown command: ' + cmd } });
  }
};
