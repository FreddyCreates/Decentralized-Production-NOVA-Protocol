///
/// NOVA PWA SERVICE WORKER — Offline-First Sovereign AI
///
/// Caches all assets for offline use, manages background sync,
/// and provides push notification support.
///

const CACHE_NAME = 'nova-protocol-v2';
const PHI = 1.6180339887498948482;
const HEARTBEAT_MS = 873;

const ASSETS_TO_CACHE = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/icons/nova-192.png',
  '/icons/nova-512.png',
  '/organism-web/organism-bridge.js',
  '/organism-web/engine-worker.js',
  '/organism-web/agent-worker.js',
  '/organism-web/memory-worker.js',
  '/organism-web/routing-worker.js',
  '/organism-web/protocol-worker.js',
  '/organism-web/safety-worker.js',
  '/organism-web/shield-worker.js',
  '/organism-web/crypto-worker.js',
  '/organism-web/render-worker.js',
  '/organism-web/production-worker.js',
  '/organism-web/extension-worker.js',
  '/organism-web/telemetry-worker.js',
  '/organism-web/infra-worker.js',
  '/organism-web/scheduler-worker.js',
  '/organism-web/stream-worker.js',
  '/organism-web/contract-worker.js',
  '/organism-web/marketplace-worker.js',
  '/organism-web/university-worker.js',
  '/organism-web/career-worker.js',
  '/workspace/settings/nova-os.json',
  '/workspace/admin/admin.json',
  '/workspace/projects/registry.json',
];

// ══════════════════════════════════════════════════════════════════
//  INSTALL — Cache all assets
// ══════════════════════════════════════════════════════════════════

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[NOVA SW] Caching', ASSETS_TO_CACHE.length, 'assets');
      return cache.addAll(ASSETS_TO_CACHE);
    }).then(() => {
      console.log('[NOVA SW] Install complete. Sovereign mode ready.');
      return self.skipWaiting();
    })
  );
});

// ══════════════════════════════════════════════════════════════════
//  ACTIVATE — Clean old caches
// ══════════════════════════════════════════════════════════════════

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names.filter(n => n !== CACHE_NAME).map(n => {
          console.log('[NOVA SW] Purging old cache:', n);
          return caches.delete(n);
        })
      );
    }).then(() => {
      console.log('[NOVA SW] Activated. Claiming clients.');
      return self.clients.claim();
    })
  );
});

// ══════════════════════════════════════════════════════════════════
//  FETCH — Cache-first strategy
// ══════════════════════════════════════════════════════════════════

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;

      return fetch(event.request).then((response) => {
        // Cache new resources that are part of our origin
        if (response.ok && event.request.url.startsWith(self.location.origin)) {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return response;
      }).catch(() => {
        // Offline fallback
        if (event.request.mode === 'navigate') {
          return caches.match('/index.html');
        }
        return new Response('Offline', { status: 503 });
      });
    })
  );
});

// ══════════════════════════════════════════════════════════════════
//  MESSAGE — Handle messages from main app
// ══════════════════════════════════════════════════════════════════

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

console.log('[NOVA SW] Service worker loaded. φ =', PHI, '· Heartbeat:', HEARTBEAT_MS, 'ms');
