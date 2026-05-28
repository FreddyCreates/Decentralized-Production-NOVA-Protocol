import { Router } from 'express';
import { db } from '../db/index.js';
import { AuthRequest } from '../middleware/auth.js';

export const logsRouter = Router();

// ─── Get Logs ────────────────────────────────────────────────────────────────
logsRouter.get('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const limit = Math.min(parseInt(req.query.limit as string || '100', 10), 1000);
  const level = req.query.level as string;
  const region = req.query.region as string;

  let query = 'SELECT * FROM logs WHERE app_id = ?';
  const params: any[] = [app.id];

  if (level) {
    query += ' AND level = ?';
    params.push(level);
  }
  if (region) {
    query += ' AND region = ?';
    params.push(region);
  }

  query += ' ORDER BY timestamp DESC LIMIT ?';
  params.push(limit);

  const logs = db.conn.prepare(query).all(...params);

  res.json({ ok: true, data: logs.reverse(), request_id: (res as any).requestId });
});

// ─── Post Log (internal — used by machines) ──────────────────────────────────
logsRouter.post('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const { machine_id, region, level, message, instance } = req.body;

  db.conn.prepare(`
    INSERT INTO logs (app_id, machine_id, region, level, message, instance)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(app.id, machine_id || '', region || 'sov-1', level || 'info', message, instance || '');

  res.status(201).json({ ok: true, request_id: (res as any).requestId });
});
