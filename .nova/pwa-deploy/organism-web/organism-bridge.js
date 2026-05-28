///
/// ORGANISM BRIDGE — Sovereign Multi-Worker Orchestrator
///
/// Boots and manages 19 permanent Web Workers. Routes commands across
/// the full organism substrate. Exposes window.organism for developer access.
///
/// 19 Workers · 40 AI Engines · 40 Alpha Agents · 10 Protocols · 20 Extensions
/// 9 Rings · Full Shields · University Hub · Career Houses · Production Lines
///

(function() {
  'use strict';

  // ══════════════════════════════════════════════════════════════
  //  WORKER REGISTRY — 19 Permanent Workers
  // ══════════════════════════════════════════════════════════════

  var WORKER_DEFS = [
    { name:'engine',      file:'engine-worker.js',      house:'Brain' },
    { name:'agent',       file:'agent-worker.js',       house:'Brain' },
    { name:'memory',      file:'memory-worker.js',      house:'Brain' },
    { name:'routing',     file:'routing-worker.js',     house:'Brain' },
    { name:'protocol',    file:'protocol-worker.js',    house:'Protocol' },
    { name:'safety',      file:'safety-worker.js',      house:'Shield' },
    { name:'shield',      file:'shield-worker.js',      house:'Shield' },
    { name:'crypto',      file:'crypto-worker.js',      house:'Shield' },
    { name:'render',      file:'render-worker.js',      house:'Production' },
    { name:'production',  file:'production-worker.js',  house:'Production' },
    { name:'extension',   file:'extension-worker.js',   house:'Production' },
    { name:'telemetry',   file:'telemetry-worker.js',   house:'Infrastructure' },
    { name:'infra',       file:'infra-worker.js',       house:'Infrastructure' },
    { name:'scheduler',   file:'scheduler-worker.js',   house:'Infrastructure' },
    { name:'stream',      file:'stream-worker.js',      house:'Infrastructure' },
    { name:'contract',    file:'contract-worker.js',    house:'Market' },
    { name:'marketplace', file:'marketplace-worker.js', house:'Market' },
    { name:'university',  file:'university-worker.js',  house:'University' },
    { name:'career',      file:'career-worker.js',      house:'Career' },
  ];

  var VALID_NAMES = {};
  for (var d = 0; d < WORKER_DEFS.length; d++) VALID_NAMES[WORKER_DEFS[d].name] = true;

  // ══════════════════════════════════════════════════════════════
  //  STATE
  // ══════════════════════════════════════════════════════════════

  var workers   = new Map();
  var pending   = new Map();
  var msgId     = 0;
  var listeners = {};

  // ══════════════════════════════════════════════════════════════
  //  BOOT — Spin up all 19 workers
  // ══════════════════════════════════════════════════════════════

  function boot(basePath) {
    if (workers.size > 0) return;
    basePath = basePath || 'organism-web/';
    if (basePath.charAt(basePath.length - 1) !== '/') basePath += '/';

    for (var i = 0; i < WORKER_DEFS.length; i++) {
      (function(def) {
        var state = {
          worker: new Worker(basePath + def.file),
          booted: false,
          bootData: null,
          lastHeartbeat: null,
          lastMetrics: null,
          beats: 0,
          house: def.house,
        };

        state.worker.onmessage = function(e) {
          var msg = e.data;
          switch (msg.type) {
            case 'boot':
              state.booted = true;
              state.bootData = msg;
              emit('boot:' + def.name, msg);
              emit('boot', { worker: def.name, data: msg });
              break;

            case 'heartbeat':
              state.lastHeartbeat = msg;
              state.beats++;
              emit('heartbeat:' + def.name, msg);
              emit('heartbeat', { worker: def.name, data: msg });
              break;

            case 'metrics':
              state.lastMetrics = msg;
              state.beats++;
              emit('metrics:' + def.name, msg);
              emit('metrics', { worker: def.name, data: msg });
              break;

            case 'response':
              if (msg.id && pending.has(msg.id)) {
                if (msg.ok === false) {
                  pending.get(msg.id).reject(msg);
                } else {
                  pending.get(msg.id).resolve(msg);
                }
                pending.delete(msg.id);
              }
              emit('response:' + def.name, msg);
              break;

            case 'error':
              if (msg.id && pending.has(msg.id)) {
                pending.get(msg.id).reject(msg);
                pending.delete(msg.id);
              }
              emit('error:' + def.name, msg);
              emit('error', { worker: def.name, data: msg });
              break;
          }
        };

        state.worker.onerror = function(err) {
          emit('error:' + def.name, {
            message: err.message, filename: err.filename, lineno: err.lineno,
          });
          emit('error', { worker: def.name, data: { message: err.message } });
        };

        workers.set(def.name, state);
      })(WORKER_DEFS[i]);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SEND — Post command to a named worker
  // ══════════════════════════════════════════════════════════════

  function send(workerName, cmd, params) {
    if (!VALID_NAMES[workerName]) {
      return Promise.reject(new Error('Unknown worker: ' + workerName));
    }
    var state = workers.get(workerName);
    if (!state) {
      return Promise.reject(new Error('Worker not booted: ' + workerName));
    }
    var id = ++msgId;
    return new Promise(function(resolve, reject) {
      pending.set(id, { resolve: resolve, reject: reject });
      state.worker.postMessage(Object.assign({ cmd: cmd, id: id }, params || {}));
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  CONVENIENCE METHODS
  // ══════════════════════════════════════════════════════════════

  function dispatch(capability, payload) {
    return send('engine', 'dispatch', { capability: capability, payload: payload || '' });
  }
  function route(capability) {
    return send('routing', 'route', { capability: capability });
  }
  function encrypt(data) {
    return send('crypto', 'encrypt', { data: data });
  }
  function scan(type, payload) {
    return send('safety', 'scan', { type: type, payload: payload });
  }
  function activateShields() {
    return send('shield', 'activate', {});
  }
  function enroll(courseId) {
    return send('university', 'enroll', { courseId: courseId });
  }
  function train(skill, xp) {
    return send('career', 'train', { skill: skill, xpGain: xp });
  }
  function build(productId) {
    return send('production', 'build', { productId: productId });
  }
  function price(callId, surface) {
    return send('marketplace', 'price', { callId: callId, surface: surface });
  }
  function record(name, value) {
    return send('telemetry', 'record', { name: name, value: value });
  }

  // ══════════════════════════════════════════════════════════════
  //  EVENT SYSTEM
  // ══════════════════════════════════════════════════════════════

  function on(event, callback) {
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(callback);
  }

  function off(event, callback) {
    if (!listeners[event]) return;
    listeners[event] = listeners[event].filter(function(cb) { return cb !== callback; });
  }

  function emit(event, data) {
    if (!listeners[event]) return;
    for (var i = 0; i < listeners[event].length; i++) {
      try { listeners[event][i](data); } catch(_) {}
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  STATUS
  // ══════════════════════════════════════════════════════════════

  function status() {
    var result = {};
    workers.forEach(function(state, name) {
      result[name] = {
        booted: state.booted,
        beats: state.beats,
        house: state.house,
        lastMetrics: state.lastMetrics,
      };
    });
    return { workers: result, pending: pending.size };
  }

  function fleetStatus() {
    var booted = 0;
    var houses = { Brain:0, Protocol:0, Shield:0, Production:0, Infrastructure:0, Market:0, University:0, Career:0 };
    workers.forEach(function(state) {
      if (state.booted) booted++;
      houses[state.house]++;
    });
    return { total: 19, booted: booted, houses: houses };
  }

  // ══════════════════════════════════════════════════════════════
  //  EXPOSE — window.organism
  // ══════════════════════════════════════════════════════════════

  var organism = {
    boot:           boot,
    send:           send,
    dispatch:       dispatch,
    route:          route,
    encrypt:        encrypt,
    scan:           scan,
    activateShields:activateShields,
    enroll:         enroll,
    train:          train,
    build:          build,
    price:          price,
    record:         record,
    on:             on,
    off:            off,
    status:         status,
    fleetStatus:    fleetStatus,
    WORKER_DEFS:    WORKER_DEFS,
  };

  if (typeof window !== 'undefined') {
    window.organism = organism;
  }

  // ══════════════════════════════════════════════════════════════
  //  AUTO-BOOT on DOMContentLoaded
  // ══════════════════════════════════════════════════════════════

  if (typeof window !== 'undefined') {
    window.addEventListener('DOMContentLoaded', function() {
      var scripts = document.getElementsByTagName('script');
      var basePath = 'organism-web/';
      for (var i = 0; i < scripts.length; i++) {
        var src = scripts[i].getAttribute('src') || '';
        if (src.indexOf('organism-bridge') !== -1) {
          basePath = src.replace(/organism-bridge\.js.*$/, '');
          break;
        }
      }
      boot(basePath);
    });
  }

})();
