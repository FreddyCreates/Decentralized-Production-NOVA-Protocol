import { Router } from 'express';
import { nanoid } from 'nanoid';
import { db } from '../db/index.js';
import { AuthRequest } from '../middleware/auth.js';

export const machinesRouter = Router();

// ─── List Machines for App ───────────────────────────────────────────────────
machinesRouter.get('/', (req: AuthRequest, res) => {
  const appName = req.query.app as string;
  if (!appName) {
    return res.status(400).json({ ok: false, error: 'app query parameter required' });
  }

  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const machines = db.conn.prepare(
    "SELECT * FROM machines WHERE app_id = ? AND status != 'destroyed' ORDER BY created_at DESC"
  ).all(app.id);

  res.json({ ok: true, data: machines, request_id: (res as any).requestId });
});

// ─── Get Machine ─────────────────────────────────────────────────────────────
machinesRouter.get('/:machineId', (req: AuthRequest, res) => {
  const machine = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(req.params.machineId) as any;
  if (!machine) {
    return res.status(404).json({ ok: false, error: 'Machine not found' });
  }

  // Verify ownership
  const app = db.conn.prepare('SELECT * FROM apps WHERE id = ? AND org_id = ?').get(machine.app_id, req.orgId);
  if (!app) {
    return res.status(404).json({ ok: false, error: 'Machine not found' });
  }

  res.json({ ok: true, data: machine, request_id: (res as any).requestId });
});

// ─── Stop Machine ────────────────────────────────────────────────────────────
machinesRouter.post('/:machineId/stop', (req: AuthRequest, res) => {
  const machine = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(req.params.machineId) as any;
  if (!machine) {
    return res.status(404).json({ ok: false, error: 'Machine not found' });
  }

  db.conn.prepare("UPDATE machines SET status = 'stopped', updated_at = datetime('now') WHERE id = ?").run(machine.id);
  const updated = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(machine.id);

  res.json({ ok: true, data: updated, request_id: (res as any).requestId });
});

// ─── Start Machine ───────────────────────────────────────────────────────────
machinesRouter.post('/:machineId/start', (req: AuthRequest, res) => {
  const machine = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(req.params.machineId) as any;
  if (!machine) {
    return res.status(404).json({ ok: false, error: 'Machine not found' });
  }

  db.conn.prepare("UPDATE machines SET status = 'running', updated_at = datetime('now') WHERE id = ?").run(machine.id);
  const updated = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(machine.id);

  res.json({ ok: true, data: updated, request_id: (res as any).requestId });
});

// ─── Destroy Machine ─────────────────────────────────────────────────────────
machinesRouter.delete('/:machineId', (req: AuthRequest, res) => {
  const machine = db.conn.prepare('SELECT * FROM machines WHERE id = ?').get(req.params.machineId) as any;
  if (!machine) {
    return res.status(404).json({ ok: false, error: 'Machine not found' });
  }

  db.conn.prepare("UPDATE machines SET status = 'destroyed', updated_at = datetime('now') WHERE id = ?").run(machine.id);

  res.json({ ok: true, data: { destroyed: machine.id }, request_id: (res as any).requestId });
});
