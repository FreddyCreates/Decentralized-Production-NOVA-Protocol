import { Router } from 'express';
import { nanoid } from 'nanoid';
import { db } from '../db/index.js';
import { AuthRequest } from '../middleware/auth.js';

export const appsRouter = Router();

// ─── List Apps ───────────────────────────────────────────────────────────────
appsRouter.get('/', (req: AuthRequest, res) => {
  const apps = db.conn.prepare('SELECT * FROM apps WHERE org_id = ? ORDER BY created_at DESC').all(req.orgId);
  res.json({ ok: true, data: apps, request_id: (res as any).requestId });
});

// ─── Create App ──────────────────────────────────────────────────────────────
appsRouter.post('/', (req: AuthRequest, res) => {
  const { app_name, region } = req.body;

  if (!app_name) {
    return res.status(400).json({ ok: false, error: 'app_name required' });
  }

  // Validate app name
  if (!/^[a-z][a-z0-9-]{2,28}[a-z0-9]$/.test(app_name)) {
    return res.status(400).json({
      ok: false,
      error: 'App name must be 4-30 chars, lowercase alphanumeric with hyphens, start with letter',
    });
  }

  const existing = db.conn.prepare('SELECT id FROM apps WHERE name = ?').get(app_name);
  if (existing) {
    return res.status(409).json({ ok: false, error: `App '${app_name}' already exists` });
  }

  const appId = `app_${nanoid(16)}`;
  const hostname = `${app_name}.novacloud.run`;
  const regions = JSON.stringify([region || 'sov-1']);

  db.conn.prepare(`
    INSERT INTO apps (id, name, org_id, status, hostname, regions)
    VALUES (?, ?, ?, 'pending', ?, ?)
  `).run(appId, app_name, req.orgId, hostname, regions);

  const app = db.conn.prepare('SELECT * FROM apps WHERE id = ?').get(appId);

  res.status(201).json({ ok: true, data: app, request_id: (res as any).requestId });
});

// ─── Get App ─────────────────────────────────────────────────────────────────
appsRouter.get('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }
  res.json({ ok: true, data: app, request_id: (res as any).requestId });
});

// ─── Delete App ──────────────────────────────────────────────────────────────
appsRouter.delete('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  // Destroy all machines
  db.conn.prepare("UPDATE machines SET status = 'destroyed' WHERE app_id = ?").run(app.id);
  db.conn.prepare("UPDATE apps SET status = 'stopped' WHERE id = ?").run(app.id);
  db.conn.prepare('DELETE FROM apps WHERE id = ?').run(app.id);

  res.json({ ok: true, data: { deleted: app.name }, request_id: (res as any).requestId });
});

// ─── Update App Status ───────────────────────────────────────────────────────
appsRouter.patch('/:appName/status', (req: AuthRequest, res) => {
  const { status } = req.body;
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  db.conn.prepare("UPDATE apps SET status = ?, updated_at = datetime('now') WHERE id = ?").run(status, app.id);
  const updated = db.conn.prepare('SELECT * FROM apps WHERE id = ?').get(app.id);
  res.json({ ok: true, data: updated, request_id: (res as any).requestId });
});

// ─── Scale App ───────────────────────────────────────────────────────────────
appsRouter.post('/:appName/scale', (req: AuthRequest, res) => {
  const { count, region, cpus, memory_mb } = req.body;
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const targetRegion = region || 'sov-1';
  const currentMachines = db.conn.prepare(
    "SELECT * FROM machines WHERE app_id = ? AND region = ? AND status != 'destroyed'"
  ).all(app.id, targetRegion) as any[];

  const diff = count - currentMachines.length;

  if (diff > 0) {
    // Scale up — create machines
    for (let i = 0; i < diff; i++) {
      const machineId = `mch_${nanoid(16)}`;
      const name = `${app.name}-${targetRegion}-${nanoid(4)}`;
      const privateIp = `fdaa:0:1::${Math.floor(Math.random() * 65535).toString(16)}`;

      db.conn.prepare(`
        INSERT INTO machines (id, app_id, name, status, region, instance_id, private_ip, image, cpus, memory_mb)
        VALUES (?, ?, ?, 'starting', ?, ?, ?, ?, ?, ?)
      `).run(machineId, app.id, name, targetRegion, nanoid(8), privateIp, app.current_release_id || 'pending', cpus || 1, memory_mb || 256);
    }
  } else if (diff < 0) {
    // Scale down — destroy excess machines
    const toRemove = currentMachines.slice(0, Math.abs(diff));
    for (const m of toRemove) {
      db.conn.prepare("UPDATE machines SET status = 'stopping' WHERE id = ?").run(m.id);
    }
  }

  const machines = db.conn.prepare(
    "SELECT * FROM machines WHERE app_id = ? AND status != 'destroyed'"
  ).all(app.id);

  db.conn.prepare("UPDATE apps SET status = 'running', updated_at = datetime('now') WHERE id = ?").run(app.id);

  res.json({
    ok: true,
    data: { app: app.name, region: targetRegion, count, machines },
    request_id: (res as any).requestId,
  });
});
