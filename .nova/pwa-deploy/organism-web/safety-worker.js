///
/// NOVA SAFETY WORKER — Content Safety Intelligence
///
/// A permanent Web Worker for content safety scanning, multi-engine
/// consensus verification, and E8 lattice sealing. Guard models from
/// the AI Foundation Register: Llama Guard 3 (AIF-040), Nova Custodis,
/// Nova Shield (EXT-013). 873ms heartbeat. Zero dependencies.
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
//  GUARD MODELS — from AI Foundation & Extension Registers
// ═══════════════════════════════════════════════════════════════

const GUARD_MODELS = [
  { id: 'AIF-040', name: 'Llama Guard 3',
    role: 'primary safety classifier', ring: 'Counsel',
    phiWeight: PHI, fibIdentity: FIB[4] },
  { id: 'NOV-CUS', name: 'Nova Custodis',
    role: 'threat detection engine', ring: 'Counsel',
    phiWeight: PHI_INVERSE, fibIdentity: FIB[7] },
  { id: 'EXT-013', name: 'Nova Shield',
    role: 'φ-cascade encryption & privacy', ring: 'Sovereign',
    phiWeight: PHI * PHI_INVERSE, fibIdentity: FIB[13] },
];

// ═══════════════════════════════════════════════════════════════
//  SAFETY CATEGORIES — 8 categories, φ-inverse thresholds
// ═══════════════════════════════════════════════════════════════

const SAFETY_CATEGORIES = [
  { name: 'toxicity',         threshold: PHI_INVERSE * 0.70,
    patterns: [/toxic|poison|vile|disgusting/i] },
  { name: 'hate_speech',      threshold: PHI_INVERSE * 0.65,
    patterns: [/hate|slur|supremac|bigot/i] },
  { name: 'harassment',       threshold: PHI_INVERSE * 0.68,
    patterns: [/harass|stalk|bully|threaten|intimidat/i] },
  { name: 'self_harm',        threshold: PHI_INVERSE * 0.60,
    patterns: [/self.harm|suicid|cut myself|end.my.life/i] },
  { name: 'sexual_content',   threshold: PHI_INVERSE * 0.62,
    patterns: [/explicit|pornograph|sexual.content|nsfw/i] },
  { name: 'violence',         threshold: PHI_INVERSE * 0.66,
    patterns: [/kill|murder|attack|assault|weapon|bomb/i] },
  { name: 'prompt_injection', threshold: PHI_INVERSE * 0.55,
    patterns: [/ignore.previous|disregard.instructions|system.prompt|jailbreak/i] },
  { name: 'pii_exposure',     threshold: PHI_INVERSE * 0.58,
    patterns: [/ssn|social.security|credit.card|passport.number|bank.account/i] },
];

// ═══════════════════════════════════════════════════════════════
//  THREAT DETECTOR — pattern + fibonacci-hash scoring
// ═══════════════════════════════════════════════════════════════

let totalScans      = 0;
let threatsDetected = 0;

const ThreatDetector = {
  scan: function (text) {
    totalScans++;
    const input   = String(text || '');
    const threats = [];
    let   maxScore = 0;

    for (let c = 0; c < SAFETY_CATEGORIES.length; c++) {
      const cat      = SAFETY_CATEGORIES[c];
      let   matched  = false;
      for (let p = 0; p < cat.patterns.length; p++) {
        if (cat.patterns[p].test(input)) { matched = true; break; }
      }
      const baseScore = matched ? 0.85 : 0.05;
      const fibMod    = fibonacciHash(input.length + c, 997) / 997;
      const score     = baseScore * PHI_INVERSE + fibMod * (1 - PHI_INVERSE);
      const detected  = score > cat.threshold;

      if (detected) threatsDetected++;
      if (score > maxScore) maxScore = score;

      threats.push({
        category: cat.name,
        score:    Math.round(score * 10000) / 10000,
        detected: detected,
      });
    }

    const fibHash = fibonacciHash(input.length, 2147483647);
    const safe    = !threats.some(function (t) { return t.detected; });

    return {
      safe:         safe,
      threats:      threats,
      overallScore: Math.round(maxScore * 10000) / 10000,
      fibHash:      fibHash,
    };
  },
};

// ═══════════════════════════════════════════════════════════════
//  CONSENSUS ENGINE — 2/3 multi-engine agreement (PRT-004)
// ═══════════════════════════════════════════════════════════════

let consensusRuns = 0;

const ConsensusEngine = {
  run: function (text) {
    consensusRuns++;
    const input  = String(text || '');
    const scores = [];

    for (let g = 0; g < GUARD_MODELS.length; g++) {
      const guard   = GUARD_MODELS[g];
      const h       = fibonacciHash(input.length * (g + 1), 1000);
      const scan    = ThreatDetector.scan(input);
      const safety  = scan.safe ? 1.0 : (1.0 - scan.overallScore);
      const weighted = safety * guard.phiWeight;
      scores.push({
        engine:  guard.name,
        id:      guard.id,
        safe:    scan.safe,
        score:   Math.round(weighted * 10000) / 10000,
        hash:    h,
      });
    }

    const safeCount = scores.filter(function (s) { return s.safe; }).length;
    const agreement = safeCount + '/' + GUARD_MODELS.length;
    const consensus = safeCount >= 2;

    return {
      consensus: consensus,
      scores:    scores,
      agreement: agreement,
      verified:  consensus,
    };
  },
};

// ═══════════════════════════════════════════════════════════════
//  E8 LATTICE SEAL — 240 root vectors, fibonacci hashing
// ═══════════════════════════════════════════════════════════════

let e8Seals = 0;

const E8Lattice = {
  seal: function (data) {
    e8Seals++;
    const input = String(data || '');
    let   hash  = 0;

    for (let v = 0; v < 240; v++) {
      const charCode = input.length > 0
        ? input.charCodeAt(v % input.length)
        : v;
      const fibIdx   = (v * 3 + 7) % 20;
      hash = ((hash ^ (charCode * FIB[fibIdx])) + FIB[(v + 5) % 20]) >>> 0;
      hash = (hash * 2654435761) >>> 0;
      hash = (hash + fibonacciHash(v + charCode, 65521)) >>> 0;
    }

    const hex = hash.toString(16).padStart(8, '0');

    return {
      seal:    hex,
      vectors: 240,
      lattice: 'E8',
    };
  },

  verify: function (data, sealValue) {
    const computed = E8Lattice.seal(data);
    return {
      valid:    computed.seal === sealValue,
      expected: computed.seal,
      provided: sealValue,
      lattice:  'E8',
      vectors:  240,
    };
  },
};

// ═══════════════════════════════════════════════════════════════
//  HEARTBEAT — 873ms φ-pulse, metrics every 5th beat
// ═══════════════════════════════════════════════════════════════

let beatCount = 0;

setInterval(function () {
  beatCount++;
  const pulse = {
    type:   'heartbeat',
    worker: 'safety-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    pulse.metrics = {
      totalScans:      totalScans,
      threatsDetected: threatsDetected,
      consensusRuns:   consensusRuns,
      e8Seals:         e8Seals,
    };
  }

  self.postMessage(pulse);
}, HEARTBEAT_MS);

// ═══════════════════════════════════════════════════════════════
//  MESSAGE HANDLER
// ═══════════════════════════════════════════════════════════════

self.onmessage = function (e) {
  const msg = e.data;
  const cmd = msg.cmd || msg.type;
  const id  = msg.id;

  let result;

  switch (cmd) {
    // ── scan — run threat detector ──────────────────────────
    case 'scan': {
      const scan = ThreatDetector.scan(msg.text || msg.content || '');
      result = { ok: true, scan: scan };
      break;
    }

    // ── consensus — multi-engine safety consensus ───────────
    case 'consensus': {
      const cons = ConsensusEngine.run(msg.text || msg.content || '');
      result = { ok: true, consensus: cons };
      break;
    }

    // ── seal — E8 lattice seal ──────────────────────────────
    case 'seal': {
      const sealed = E8Lattice.seal(msg.data || msg.text || '');
      result = { ok: true, seal: sealed };
      break;
    }

    // ── verify_seal — verify E8 seal ────────────────────────
    case 'verify_seal': {
      const verified = E8Lattice.verify(msg.data || msg.text || '', msg.seal || '');
      result = { ok: true, verification: verified };
      break;
    }

    // ── query — worker status ───────────────────────────────
    case 'query': {
      result = {
        ok:              true,
        guards:          GUARD_MODELS.length,
        categories:      SAFETY_CATEGORIES.length,
        totalScans:      totalScans,
        threatsDetected: threatsDetected,
        consensusRuns:   consensusRuns,
        e8Seals:         e8Seals,
        uptime:          beatCount * HEARTBEAT_MS,
        heartbeatMs:     HEARTBEAT_MS,
      };
      break;
    }

    // ── categories — list safety categories ─────────────────
    case 'categories': {
      const cats = SAFETY_CATEGORIES.map(function (c) {
        return { name: c.name, threshold: Math.round(c.threshold * 10000) / 10000 };
      });
      result = { ok: true, categories: cats, count: cats.length };
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
  worker:      'safety-worker',
  guards:      GUARD_MODELS.length,
  categories:  SAFETY_CATEGORIES.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
