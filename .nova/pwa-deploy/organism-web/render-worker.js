///
/// NOVA RENDER WORKER — Golden-Ratio Geometry & Phyllotaxis Layout
///
/// A permanent Web Worker for computing phyllotaxis layouts, golden spiral
/// geometries, ring topology coordinates, wire endpoints, and Fibonacci-
/// proportioned grids. The main thread renders what this worker computes.
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
//  PHYLLOTAXIS ENGINE — golden-angle point distribution
// ═══════════════════════════════════════════════════════════════

let totalLayouts = 0;
let totalSpirals = 0;
let totalGrids   = 0;

const PhyllotaxisEngine = {
  layout: function (count, radius) {
    totalLayouts++;
    const n   = Math.max(1, count || 21);
    const r   = radius || 300;
    const pts = [];

    for (let i = 0; i < n; i++) {
      const angle = i * GOLDEN_ANGLE;
      const dist  = r * Math.sqrt(i / n);
      pts.push({
        x:     Math.round(Math.cos(angle) * dist * 1000) / 1000,
        y:     Math.round(Math.sin(angle) * dist * 1000) / 1000,
        angle: Math.round(angle * 10000) / 10000,
        index: i,
      });
    }

    return pts;
  },

  spiral: function (turns, points) {
    totalSpirals++;
    const t   = turns  || 5;
    const n   = points || 100;
    const a   = 1;
    const pts = [];

    for (let i = 0; i < n; i++) {
      const theta = (i / n) * t * 2 * Math.PI;
      const r     = a * Math.pow(PHI, (2 * theta) / Math.PI);
      pts.push({
        x:     Math.round(Math.cos(theta) * r * 1000) / 1000,
        y:     Math.round(Math.sin(theta) * r * 1000) / 1000,
        r:     Math.round(r * 1000) / 1000,
        theta: Math.round(theta * 10000) / 10000,
      });
    }

    return pts;
  },
};

// ═══════════════════════════════════════════════════════════════
//  RING LAYOUT — 9 organism rings, concentric placement
// ═══════════════════════════════════════════════════════════════

const RING_DEFS = [
  { name: 'Core',       radius: 50 },
  { name: 'Sovereign',  radius: 100 },
  { name: 'Counsel',    radius: 150 },
  { name: 'Memory',     radius: 200 },
  { name: 'Proof',      radius: 250 },
  { name: 'Interface',  radius: 300 },
  { name: 'Geometry',   radius: 350 },
  { name: 'Extension',  radius: 400 },
  { name: 'Frontier',   radius: 450 },
];

const RingLayout = {
  computeRings: function (engines) {
    const items = engines || [];
    const rings = RING_DEFS.map(function (def) {
      return {
        name:    def.name,
        radius:  def.radius,
        engines: [],
      };
    });

    // Map of ring name → index
    const ringMap = {};
    for (let i = 0; i < RING_DEFS.length; i++) {
      ringMap[RING_DEFS[i].name] = i;
    }

    // Place each engine in its ring
    for (let e = 0; e < items.length; e++) {
      const eng  = items[e];
      const rIdx = ringMap[eng.ring] !== undefined ? ringMap[eng.ring] : 0;
      rings[rIdx].engines.push(eng);
    }

    // Phyllotaxis within each ring
    for (let r = 0; r < rings.length; r++) {
      const ring = rings[r];
      const n    = ring.engines.length;
      if (n === 0) continue;

      for (let i = 0; i < n; i++) {
        const angle = i * GOLDEN_ANGLE;
        const dist  = ring.radius * Math.sqrt((i + 1) / (n + 1));
        ring.engines[i] = {
          id:    ring.engines[i].id || ring.engines[i].name || 'engine-' + i,
          x:     Math.round(Math.cos(angle) * dist * 1000) / 1000,
          y:     Math.round(Math.sin(angle) * dist * 1000) / 1000,
          angle: Math.round(angle * 10000) / 10000,
        };
      }
    }

    return { rings: rings };
  },
};

// ═══════════════════════════════════════════════════════════════
//  WIRE GEOMETRY — engine-to-ring-center connections
// ═══════════════════════════════════════════════════════════════

const WireGeometry = {
  computeWires: function (engines) {
    const items = engines || [];
    const wires = [];

    for (let i = 0; i < items.length; i++) {
      const eng = items[i];
      wires.push({
        from:     { x: eng.x || 0, y: eng.y || 0 },
        to:       { x: 0, y: 0 },
        engineId: eng.id || eng.name || 'engine-' + i,
        ring:     eng.ring || 'Core',
      });
    }

    return wires;
  },
};

// ═══════════════════════════════════════════════════════════════
//  FIBONACCI GRID — Fibonacci-proportioned cell layout
// ═══════════════════════════════════════════════════════════════

const FibonacciGrid = {
  grid: function (cols, rows, width, height) {
    totalGrids++;
    const c = Math.max(1, cols   || 5);
    const r = Math.max(1, rows   || 5);
    const w = width  || 800;
    const h = height || 600;

    // Compute Fibonacci ratios for columns and rows
    const colRatios = [];
    const rowRatios = [];
    let   colSum    = 0;
    let   rowSum    = 0;

    for (let i = 0; i < c; i++) {
      const v = FIB[i % 20];
      colRatios.push(v);
      colSum += v;
    }
    for (let i = 0; i < r; i++) {
      const v = FIB[i % 20];
      rowRatios.push(v);
      rowSum += v;
    }

    const cells = [];
    let   yOff  = 0;

    for (let row = 0; row < r; row++) {
      const cellH = (rowRatios[row] / rowSum) * h;
      let   xOff  = 0;

      for (let col = 0; col < c; col++) {
        const cellW = (colRatios[col] / colSum) * w;
        cells.push({
          x:   Math.round(xOff  * 1000) / 1000,
          y:   Math.round(yOff  * 1000) / 1000,
          w:   Math.round(cellW * 1000) / 1000,
          h:   Math.round(cellH * 1000) / 1000,
          col: col,
          row: row,
        });
        xOff += cellW;
      }
      yOff += cellH;
    }

    return cells;
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
    worker: 'render-worker',
    beat:   beatCount,
    ts:     Date.now(),
  };

  if (beatCount % 5 === 0) {
    pulse.metrics = {
      totalLayouts: totalLayouts,
      totalSpirals: totalSpirals,
      totalGrids:   totalGrids,
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
    // ── phyllotaxis — golden-angle point layout ─────────────
    case 'phyllotaxis': {
      const pts = PhyllotaxisEngine.layout(msg.count, msg.radius);
      result = { ok: true, points: pts, count: pts.length };
      break;
    }

    // ── spiral — golden spiral coordinates ──────────────────
    case 'spiral': {
      const pts = PhyllotaxisEngine.spiral(msg.turns, msg.points);
      result = { ok: true, spiral: pts, count: pts.length };
      break;
    }

    // ── rings — concentric ring placement ───────────────────
    case 'rings': {
      const layout = RingLayout.computeRings(msg.engines || []);
      result = { ok: true, rings: layout.rings, totalRings: layout.rings.length };
      break;
    }

    // ── wires — engine-to-center wire endpoints ─────────────
    case 'wires': {
      const wires = WireGeometry.computeWires(msg.engines || []);
      result = { ok: true, wires: wires, count: wires.length };
      break;
    }

    // ── grid — Fibonacci-proportioned grid ──────────────────
    case 'grid': {
      const cells = FibonacciGrid.grid(msg.cols, msg.rows, msg.width, msg.height);
      result = { ok: true, cells: cells, count: cells.length };
      break;
    }

    // ── query — worker status ───────────────────────────────
    case 'query': {
      result = {
        ok:           true,
        totalLayouts: totalLayouts,
        totalSpirals: totalSpirals,
        totalGrids:   totalGrids,
        rings:        RING_DEFS.length,
        uptime:       beatCount * HEARTBEAT_MS,
        heartbeatMs:  HEARTBEAT_MS,
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
  worker:      'render-worker',
  rings:       RING_DEFS.length,
  heartbeatMs: HEARTBEAT_MS,
  phi:         PHI,
  ts:          Date.now(),
});
