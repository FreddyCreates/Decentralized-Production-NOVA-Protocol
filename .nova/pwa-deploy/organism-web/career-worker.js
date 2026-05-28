///
/// NOVA CAREER WORKER — Skill Tracking & Career Pathway Optimization
///
/// A permanent Web Worker for skill XP tracking, career role matching,
/// pathway computation, and credential verification. 8 career tracks,
/// 20 trackable skills with Fibonacci-scaled XP thresholds.
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
//  ROLES — 8 career tracks (one per division)
// ═══════════════════════════════════════════════════════════════

var ROLES = [
  { id: 'ROLE-001', name: 'Exterior Orchestrator',     division: 'Exterior',       requiredSkills: ['routing', 'api-management', 'orchestration'], entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-002', name: 'Web Intelligence Analyst',  division: 'Web',            requiredSkills: ['web-crawling', 'indexing', 'extraction'],     entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-003', name: 'Rendering Engineer',        division: 'Rendering',      requiredSkills: ['scene-rendering', 'compositing', 'rasterization'], entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-004', name: 'Data Architect',            division: 'Data',           requiredSkills: ['trees', 'graphs', 'streams', 'spatial'],      entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-005', name: 'Runtime Engineer',          division: 'Runtime',        requiredSkills: ['execution', 'scheduling', 'profiling'],       entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-006', name: 'Model Scientist',           division: 'Models',         requiredSkills: ['model-selection', 'execution', 'profiling'],  entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-007', name: 'Market Strategist',         division: 'Market',         requiredSkills: ['orchestration', 'api-management', 'scheduling'], entryLevel: 1, maxLevel: 5 },
  { id: 'ROLE-008', name: 'Infrastructure Commander',  division: 'Infrastructure', requiredSkills: ['orchestration', 'scheduling', 'sandboxing'], entryLevel: 1, maxLevel: 5 },
];

// ═══════════════════════════════════════════════════════════════
//  SKILLS — 20 trackable skills
// ═══════════════════════════════════════════════════════════════

var SKILL_NAMES = [
  'routing', 'api-management', 'orchestration',
  'web-crawling', 'indexing', 'extraction', 'caching',
  'scene-rendering', 'compositing', 'rasterization', 'animation',
  'trees', 'graphs', 'streams', 'spatial',
  'execution', 'scheduling', 'profiling', 'sandboxing',
  'model-selection',
];

var VALID_SKILLS = new Map();
for (var si = 0; si < SKILL_NAMES.length; si++) {
  VALID_SKILLS.set(SKILL_NAMES[si], true);
}

// ═══════════════════════════════════════════════════════════════
//  SKILL STORE — Map of skillName → state
// ═══════════════════════════════════════════════════════════════

var SkillStore = new Map();
for (var ski = 0; ski < SKILL_NAMES.length; ski++) {
  var sName = SKILL_NAMES[ski];
  SkillStore.set(sName, {
    level:        0,
    xp:           0,
    maxXp:        FIB[0 + 5] * 100,
    lastPractice: 0,
  });
}

// ═══════════════════════════════════════════════════════════════
//  ROLE INDEX — Map for safe lookups
// ═══════════════════════════════════════════════════════════════

var RoleIndex = new Map();
for (var ri = 0; ri < ROLES.length; ri++) {
  RoleIndex.set(ROLES[ri].id, ROLES[ri]);
}

// ═══════════════════════════════════════════════════════════════
//  COUNTERS
// ═══════════════════════════════════════════════════════════════

var totalTrainings = 0;
var totalMatches   = 0;
var totalPathways  = 0;

// ═══════════════════════════════════════════════════════════════
//  TRAIN SKILL — add XP, handle level ups
// ═══════════════════════════════════════════════════════════════

function trainSkill(skill, xpGain) {
  if (!VALID_SKILLS.has(skill)) return { error: 'unknown skill: ' + skill };

  totalTrainings++;
  var state    = SkillStore.get(skill);
  var gain     = typeof xpGain === 'number' ? xpGain : 10;
  var leveledUp = false;

  state.xp += gain;
  state.lastPractice = Date.now();

  if (state.xp >= state.maxXp && state.level < 19) {
    state.level++;
    state.xp    = state.xp - state.maxXp;
    var fibIdx  = Math.min(state.level + 5, 19);
    state.maxXp = FIB[fibIdx] * 100;
    leveledUp   = true;
  }

  return {
    skill:    skill,
    level:    state.level,
    xp:       state.xp,
    maxXp:    state.maxXp,
    leveledUp: leveledUp,
  };
}

// ═══════════════════════════════════════════════════════════════
//  MATCH ROLE — score roles against provided skills
// ═══════════════════════════════════════════════════════════════

function matchRole(skills) {
  if (!skills || skills.length === 0) return { error: 'no skills provided' };

  totalMatches++;
  var skillSet = new Map();
  for (var i = 0; i < skills.length; i++) {
    skillSet.set(skills[i], true);
  }

  var ranked = [];
  for (var r = 0; r < ROLES.length; r++) {
    var role    = ROLES[r];
    var matched = 0;
    for (var s = 0; s < role.requiredSkills.length; s++) {
      if (skillSet.has(role.requiredSkills[s])) matched++;
    }
    var ratio = matched / role.requiredSkills.length;
    var score = ratio * Math.pow(PHI, matched);
    ranked.push({
      roleId:   role.id,
      name:     role.name,
      division: role.division,
      matched:  matched,
      required: role.requiredSkills.length,
      score:    Math.round(score * 10000) / 10000,
    });
  }

  ranked.sort(function (a, b) { return b.score - a.score; });
  return { roles: ranked };
}

// ═══════════════════════════════════════════════════════════════
//  PATHWAY — compute skill gaps between roles
// ═══════════════════════════════════════════════════════════════

function pathway(fromRoleId, toRoleId) {
  var fromRole = RoleIndex.get(fromRoleId);
  var toRole   = RoleIndex.get(toRoleId);
  if (!fromRole) return { error: 'role not found: ' + fromRoleId };
  if (!toRole)   return { error: 'role not found: ' + toRoleId };

  totalPathways++;

  var fromSet = new Map();
  for (var i = 0; i < fromRole.requiredSkills.length; i++) {
    fromSet.set(fromRole.requiredSkills[i], true);
  }

  var gaps = [];
  for (var j = 0; j < toRole.requiredSkills.length; j++) {
    var sk = toRole.requiredSkills[j];
    if (!fromSet.has(sk)) gaps.push(sk);
  }

  var estimatedCredits = gaps.length * FIB[3];

  return {
    from:               fromRole.id,
    to:                 toRole.id,
    gaps:               gaps,
    recommendedCourses: gaps.map(function (g) { return 'Train: ' + g; }),
    estimatedCredits:   estimatedCredits,
  };
}

// ═══════════════════════════════════════════════════════════════
//  CREDENTIAL VERIFY — check if skills meet role requirements
// ═══════════════════════════════════════════════════════════════

function credentialVerify(roleId, skills) {
  var role = RoleIndex.get(roleId);
  if (!role) return { error: 'role not found: ' + roleId };

  var skillSet = new Map();
  if (skills) {
    for (var i = 0; i < skills.length; i++) {
      skillSet.set(skills[i], true);
    }
  }

  var missing = [];
  for (var j = 0; j < role.requiredSkills.length; j++) {
    if (!skillSet.has(role.requiredSkills[j])) {
      missing.push(role.requiredSkills[j]);
    }
  }

  var qualified      = missing.length === 0;
  var credentialHash = fibonacciHash(
    parseInt(roleId.replace('ROLE-', ''), 10) * (skills ? skills.length : 0),
    2147483647
  );

  return {
    roleId:         role.id,
    qualified:      qualified,
    missingSkills:  missing,
    credentialHash: credentialHash,
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
    worker: 'career-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    msg.type = 'metrics';

    var totalLevel = 0;
    var skillCount = 0;
    SkillStore.forEach(function (v) {
      totalLevel += v.level;
      skillCount++;
    });

    msg.metrics = {
      totalTrainings: totalTrainings,
      totalMatches:   totalMatches,
      totalPathways:  totalPathways,
      avgSkillLevel:  skillCount > 0 ? Math.round((totalLevel / skillCount) * 10000) / 10000 : 0,
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
    // ── train — train a skill ──────────────────────────────
    case 'train': {
      result = { ok: true, training: trainSkill(msg.skill, msg.xpGain) };
      break;
    }

    // ── match — match skills to roles ──────────────────────
    case 'match': {
      result = { ok: true, matching: matchRole(msg.skills) };
      break;
    }

    // ── pathway — compute career pathway ───────────────────
    case 'pathway': {
      result = { ok: true, pathway: pathway(msg.from, msg.to) };
      break;
    }

    // ── verify — credential verification ───────────────────
    case 'verify': {
      result = { ok: true, credential: credentialVerify(msg.roleId, msg.skills) };
      break;
    }

    // ── skills — list all skills ───────────────────────────
    case 'skills': {
      var skillList = [];
      SkillStore.forEach(function (v, k) {
        skillList.push({ skill: k, level: v.level, xp: v.xp, maxXp: v.maxXp });
      });
      result = { ok: true, skills: skillList, count: skillList.length };
      break;
    }

    // ── roles — list all roles ─────────────────────────────
    case 'roles': {
      var roleList = ROLES.map(function (r) {
        return { id: r.id, name: r.name, division: r.division, requiredSkills: r.requiredSkills };
      });
      result = { ok: true, roles: roleList, count: roleList.length };
      break;
    }

    // ── query — worker status ──────────────────────────────
    case 'query': {
      result = {
        ok:             true,
        roles:          ROLES.length,
        skills:         SKILL_NAMES.length,
        totalTrainings: totalTrainings,
        totalMatches:   totalMatches,
        totalPathways:  totalPathways,
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
  worker:      'career-worker',
  roles:       ROLES.length,
  skills:      SKILL_NAMES.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
