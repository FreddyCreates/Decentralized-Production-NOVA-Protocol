///
/// NOVA UNIVERSITY WORKER — Training Pipelines & Knowledge Synthesis Hub
///
/// A permanent Web Worker for curriculum management across 8 faculties,
/// 40 courses with φ-weighted credits, and knowledge graph synthesis.
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
//  FACULTIES — 8 knowledge faculties (matching 8 agent divisions)
// ═══════════════════════════════════════════════════════════════

var FACULTIES = [
  'Exterior Systems',
  'Web Intelligence',
  'Rendering Arts',
  'Data Architecture',
  'Runtime Engineering',
  'Model Science',
  'Market Economics',
  'Infrastructure Operations',
];

// ═══════════════════════════════════════════════════════════════
//  CURRICULUM — 40 courses (5 per faculty)
// ═══════════════════════════════════════════════════════════════

var LEVEL_NAMES  = ['foundational', 'intermediate', 'advanced', 'expert', 'sovereign'];
var LEVEL_FIB    = [1, 2, 3, 5, 8];

var COURSE_NAMES = [
  ['Cross-System Routing Fundamentals', 'Partner SDK Integration', 'Multi-Cloud Orchestration', 'Edge Fleet Command', 'AGI Exterior Synthesis'],
  ['Web Crawling Basics', 'Content Indexing', 'Data Extraction Patterns', 'Cache Architecture', 'Web Pipeline Mastery'],
  ['Scene Composition 101', 'Multi-Layer Compositing', 'GPU Rasterization', 'Physics Animation', 'Rendering Pipeline AGI'],
  ['Tree Structures', 'Graph Algorithms', 'Stream Processing', 'Spatial Indexing', 'Data Structure Synthesis'],
  ['Code Execution Sandbox', 'Fibonacci Scheduling', 'Runtime Profiling', 'Process Isolation', 'Runtime Orchestration AGI'],
  ['Model Selection Theory', 'Multi-Model Fusion', 'Quality Evaluation', 'Sovereign Training', 'Model Lifecycle AGI'],
  ['Dynamic Pricing', 'Market Auditing', 'Load Balancing Theory', 'Contract Law', 'Market AGI Strategy'],
  ['Health Monitoring', 'Fibonacci Auto-Scaling', 'Deployment Orchestration', 'Disaster Recovery', 'Infrastructure AGI'],
];

var CURRICULUM = [];
var courseNum  = 1;

for (var fi = 0; fi < FACULTIES.length; fi++) {
  for (var li = 0; li < 5; li++) {
    var padded = String(courseNum);
    while (padded.length < 3) padded = '0' + padded;
    CURRICULUM.push({
      id:        'CUR-' + padded,
      faculty:   FACULTIES[fi],
      name:      COURSE_NAMES[fi][li],
      level:     LEVEL_NAMES[li],
      credits:   LEVEL_FIB[li],
      enrolled:  0,
      graduated: 0,
      phiWeight: Math.pow(PHI, li),
    });
    courseNum++;
  }
}

// ═══════════════════════════════════════════════════════════════
//  COURSE INDEX — Map for safe lookups
// ═══════════════════════════════════════════════════════════════

var CourseIndex = new Map();
for (var ci = 0; ci < CURRICULUM.length; ci++) {
  CourseIndex.set(CURRICULUM[ci].id, CURRICULUM[ci]);
}

// ═══════════════════════════════════════════════════════════════
//  KNOWLEDGE GRAPH — concept synthesis store
// ═══════════════════════════════════════════════════════════════

var KNOWLEDGE_GRAPH = new Map();
var nextSynthesisId = 1;

// ═══════════════════════════════════════════════════════════════
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalEnrolled   = 0;
var totalGraduated  = 0;
var totalSyntheses  = 0;

// ═══════════════════════════════════════════════════════════════
//  ENROLL — enroll in a course
// ═══════════════════════════════════════════════════════════════

function enroll(courseId) {
  var course = CourseIndex.get(courseId);
  if (!course) return { error: 'course not found: ' + courseId };

  course.enrolled++;
  totalEnrolled++;

  return {
    courseId:  course.id,
    enrolled: course.enrolled,
    credits:  course.credits,
  };
}

// ═══════════════════════════════════════════════════════════════
//  GRADUATE — graduate from a course
// ═══════════════════════════════════════════════════════════════

function graduate(courseId) {
  var course = CourseIndex.get(courseId);
  if (!course) return { error: 'course not found: ' + courseId };

  course.graduated++;
  totalGraduated++;

  var numPart = parseInt(courseId.replace('CUR-', ''), 10) || 0;
  var diplomaHash = fibonacciHash(numPart, 2147483648);

  return {
    courseId:     course.id,
    graduated:   course.graduated,
    diplomaHash: diplomaHash,
  };
}

// ═══════════════════════════════════════════════════════════════
//  SYNTHESIZE — combine concepts into new knowledge
// ═══════════════════════════════════════════════════════════════

function synthesize(concepts) {
  if (!concepts || concepts.length === 0) return { error: 'no concepts provided' };

  totalSyntheses++;
  var synthId = nextSynthesisId++;

  var combined = concepts.join('+');
  var depth    = concepts.length;
  var phiW     = Math.pow(PHI, depth);
  var fibHash  = fibonacciHash(combined.length * depth, 2147483647);

  var newConcept = 'SYNTH-' + synthId;
  KNOWLEDGE_GRAPH.set(newConcept, {
    concept:     newConcept,
    connections: concepts.slice(),
    weight:      Math.round(phiW * 10000) / 10000,
    synthesized: true,
  });

  for (var i = 0; i < concepts.length; i++) {
    var cId = concepts[i];
    if (!KNOWLEDGE_GRAPH.has(cId)) {
      KNOWLEDGE_GRAPH.set(cId, {
        concept:     cId,
        connections: [],
        weight:      1.0,
        synthesized: false,
      });
    }
    KNOWLEDGE_GRAPH.get(cId).connections.push(newConcept);
  }

  return {
    synthesisId:  synthId,
    concepts:     concepts,
    newKnowledge: newConcept,
    phiWeight:    Math.round(phiW * 10000) / 10000,
    fibHash:      fibHash,
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
    worker: 'university-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';

    var coursesByFaculty = Object.create(null);
    for (var i = 0; i < FACULTIES.length; i++) {
      coursesByFaculty[FACULTIES[i]] = 0;
    }
    for (var j = 0; j < CURRICULUM.length; j++) {
      coursesByFaculty[CURRICULUM[j].faculty]++;
    }

    msg.metrics = {
      totalEnrolled:   totalEnrolled,
      totalGraduated:  totalGraduated,
      totalSyntheses:  totalSyntheses,
      coursesByFaculty: coursesByFaculty,
      knowledgeNodes:  KNOWLEDGE_GRAPH.size,
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
    // ── enroll — enroll in a course ────────────────────────
    case 'enroll': {
      result = { ok: true, enrollment: enroll(msg.courseId) };
      break;
    }

    // ── graduate — graduate from a course ──────────────────
    case 'graduate': {
      result = { ok: true, graduation: graduate(msg.courseId) };
      break;
    }

    // ── synthesize — combine concepts ──────────────────────
    case 'synthesize': {
      result = { ok: true, synthesis: synthesize(msg.concepts) };
      break;
    }

    // ── courses — list all courses ─────────────────────────
    case 'courses': {
      var courseList = CURRICULUM.map(function (c) {
        return {
          id:        c.id,
          faculty:   c.faculty,
          name:      c.name,
          level:     c.level,
          credits:   c.credits,
          enrolled:  c.enrolled,
          graduated: c.graduated,
          phiWeight: Math.round(c.phiWeight * 10000) / 10000,
        };
      });
      result = { ok: true, courses: courseList, count: courseList.length };
      break;
    }

    // ── faculties — list faculties ──────────────────────────
    case 'faculties': {
      result = { ok: true, faculties: FACULTIES, count: FACULTIES.length };
      break;
    }

    // ── knowledge — dump knowledge graph ───────────────────
    case 'knowledge': {
      var nodes = [];
      KNOWLEDGE_GRAPH.forEach(function (v, k) {
        nodes.push({ id: k, connections: v.connections.length, weight: v.weight, synthesized: v.synthesized });
      });
      result = { ok: true, knowledge: nodes, count: nodes.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:             true,
        faculties:      FACULTIES.length,
        courses:        CURRICULUM.length,
        totalEnrolled:  totalEnrolled,
        totalGraduated: totalGraduated,
        totalSyntheses: totalSyntheses,
        knowledgeNodes: KNOWLEDGE_GRAPH.size,
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
  worker:      'university-worker',
  faculties:   FACULTIES.length,
  courses:     CURRICULUM.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
