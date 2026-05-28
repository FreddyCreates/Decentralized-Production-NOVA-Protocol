///
/// NOVA Cloud Platform — API Server
///
/// The control plane. This is your fly.io API equivalent.
/// Manages apps, machines, deployments, secrets, logs.
///
/// Casa de Medina — Sovereign Edge Cloud
///

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { nanoid } from 'nanoid';
import pino from 'pino';
import { appsRouter } from './routes/apps.js';
import { machinesRouter } from './routes/machines.js';
import { deploymentsRouter } from './routes/deployments.js';
import { secretsRouter } from './routes/secrets.js';
import { logsRouter } from './routes/logs.js';
import { regionsRouter } from './routes/regions.js';
import { authRouter } from './routes/auth.js';
import { authMiddleware } from './middleware/auth.js';
import { requestId } from './middleware/request-id.js';
import { rateLimit } from './middleware/rate-limit.js';
import { db } from './db/index.js';

const logger = pino({ name: 'nova-cloud-api' });

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/ws/logs' });

// ─── Middleware ──────────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json({ limit: '50mb' }));
app.use(requestId);

// ─── Health & Info ───────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', platform: 'nova-cloud', version: '0.1.0' });
});

app.get('/', (_req, res) => {
  res.json({
    name: 'NOVA Cloud Platform API',
    version: '0.1.0',
    docs: '/docs',
    description: 'Sovereign Edge Cloud — Your Infrastructure, Your Rules',
  });
});

// ─── Public Routes ───────────────────────────────────────────────────────────
app.use('/v1/auth', rateLimit({ windowMs: 60_000, max: 10 }), authRouter);

// ─── Protected Routes ────────────────────────────────────────────────────────
app.use('/v1/apps', authMiddleware, rateLimit({ windowMs: 60_000, max: 100 }), appsRouter);
app.use('/v1/machines', authMiddleware, rateLimit({ windowMs: 60_000, max: 100 }), machinesRouter);
app.use('/v1/deployments', authMiddleware, rateLimit({ windowMs: 60_000, max: 30 }), deploymentsRouter);
app.use('/v1/secrets', authMiddleware, rateLimit({ windowMs: 60_000, max: 50 }), secretsRouter);
app.use('/v1/logs', authMiddleware, rateLimit({ windowMs: 60_000, max: 200 }), logsRouter);
app.use('/v1/regions', authMiddleware, rateLimit({ windowMs: 60_000, max: 100 }), regionsRouter);

// ─── WebSocket for live logs ─────────────────────────────────────────────────
wss.on('connection', (ws, req) => {
  const appId = new URL(req.url || '', 'http://localhost').searchParams.get('app');
  if (!appId) {
    ws.close(4000, 'app query parameter required');
    return;
  }

  logger.info({ appId }, 'Log stream connected');

  const interval = setInterval(() => {
    ws.ping();
  }, 30000);

  ws.on('close', () => {
    clearInterval(interval);
    logger.info({ appId }, 'Log stream disconnected');
  });
});

// ─── Error Handler ───────────────────────────────────────────────────────────
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({
    ok: false,
    error: err.message || 'Internal server error',
    request_id: (res as any).requestId || 'unknown',
  });
});

// ─── Start ───────────────────────────────────────────────────────────────────
const PORT = parseInt(process.env.NOVA_API_PORT || '4000', 10);

db.initialize();

server.listen(PORT, () => {
  logger.info(`
╔══════════════════════════════════════════════════════════════╗
║            NOVA CLOUD PLATFORM — API SERVER                  ║
║                                                              ║
║   Sovereign Edge Cloud • Your fly.io • YOUR infrastructure   ║
║                                                              ║
║   API:       http://localhost:${PORT}                           ║
║   WebSocket: ws://localhost:${PORT}/ws/logs                     ║
║   Health:    http://localhost:${PORT}/health                    ║
╚══════════════════════════════════════════════════════════════╝
  `);
});

export { app, server, wss, logger };
