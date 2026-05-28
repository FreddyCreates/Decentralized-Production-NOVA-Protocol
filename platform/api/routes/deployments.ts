import { Router } from 'express';
import { nanoid } from 'nanoid';
import { db } from '../db/index.js';
import { AuthRequest } from '../middleware/auth.js';

export const deploymentsRouter = Router();

// ─── Deploy (Create Release) ─────────────────────────────────────────────────
deploymentsRouter.post('/', (req: AuthRequest, res) => {
  const { app_name, image, strategy, definition } = req.body;

  if (!app_name || !image) {
    return res.status(400).json({ ok: false, error: 'app_name and image required' });
  }

  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(app_name, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  // Get next version number
  const lastRelease = db.conn.prepare('SELECT MAX(version) as max_v FROM releases WHERE app_id = ?').get(app.id) as any;
  const version = (lastRelease?.max_v || 0) + 1;

  const releaseId = `rel_${nanoid(16)}`;
  const def = JSON.stringify(definition || { processes: { app: { cmd: [], cpus: 1, memory_mb: 256, count: 1 } }, env: {}, services: [] });

  db.conn.prepare(`
    INSERT INTO releases (id, app_id, version, image, status, strategy, deployed_by, definition)
    VALUES (?, ?, ?, ?, 'building', ?, ?, ?)
  `).run(releaseId, app.id, version, image, strategy || 'rolling', req.userId, def);

  // Update app
  db.conn.prepare("UPDATE apps SET current_release_id = ?, status = 'deploying', updated_at = datetime('now') WHERE id = ?")
    .run(releaseId, app.id);

  // Simulate deploy progression
  setTimeout(() => {
    db.conn.prepare("UPDATE releases SET status = 'pushing' WHERE id = ?").run(releaseId);
  }, 500);

  setTimeout(() => {
    db.conn.prepare("UPDATE releases SET status = 'placing' WHERE id = ?").run(releaseId);
  }, 1500);

  setTimeout(() => {
    db.conn.prepare("UPDATE releases SET status = 'complete' WHERE id = ?").run(releaseId);
    db.conn.prepare("UPDATE apps SET status = 'running', updated_at = datetime('now') WHERE id = ?").run(app.id);

    // Start machines if none exist
    const machines = db.conn.prepare("SELECT * FROM machines WHERE app_id = ? AND status != 'destroyed'").all(app.id);
    if (machines.length === 0) {
      const regions = JSON.parse(app.regions || '["sov-1"]');
      for (const region of regions) {
        const machineId = `mch_${nanoid(16)}`;
        const name = `${app.name}-${region}-${nanoid(4)}`;
        const privateIp = `fdaa:0:1::${Math.floor(Math.random() * 65535).toString(16)}`;

        db.conn.prepare(`
          INSERT INTO machines (id, app_id, name, status, region, instance_id, private_ip, image, cpus, memory_mb)
          VALUES (?, ?, ?, 'running', ?, ?, ?, ?, 1, 256)
        `).run(machineId, app.id, name, region, nanoid(8), privateIp, image);
      }
    } else {
      // Update existing machines with new image
      db.conn.prepare("UPDATE machines SET image = ?, status = 'running', updated_at = datetime('now') WHERE app_id = ? AND status != 'destroyed'")
        .run(image, app.id);
    }
  }, 3000);

  const release = db.conn.prepare('SELECT * FROM releases WHERE id = ?').get(releaseId);

  res.status(201).json({ ok: true, data: release, request_id: (res as any).requestId });
});

// ─── List Releases ───────────────────────────────────────────────────────────
deploymentsRouter.get('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const releases = db.conn.prepare('SELECT * FROM releases WHERE app_id = ? ORDER BY version DESC LIMIT 25').all(app.id);

  res.json({ ok: true, data: releases, request_id: (res as any).requestId });
});

// ─── Get Release ─────────────────────────────────────────────────────────────
deploymentsRouter.get('/:appName/:releaseId', (req: AuthRequest, res) => {
  const release = db.conn.prepare('SELECT * FROM releases WHERE id = ?').get(req.params.releaseId) as any;
  if (!release) {
    return res.status(404).json({ ok: false, error: 'Release not found' });
  }

  res.json({ ok: true, data: release, request_id: (res as any).requestId });
});

// ─── Rollback ────────────────────────────────────────────────────────────────
deploymentsRouter.post('/:appName/rollback', (req: AuthRequest, res) => {
  const { version } = req.body;
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const targetRelease = db.conn.prepare('SELECT * FROM releases WHERE app_id = ? AND version = ?').get(app.id, version) as any;
  if (!targetRelease) {
    return res.status(404).json({ ok: false, error: `Release v${version} not found` });
  }

  // Create a new release pointing to old image
  const lastRelease = db.conn.prepare('SELECT MAX(version) as max_v FROM releases WHERE app_id = ?').get(app.id) as any;
  const newVersion = (lastRelease?.max_v || 0) + 1;
  const releaseId = `rel_${nanoid(16)}`;

  db.conn.prepare(`
    INSERT INTO releases (id, app_id, version, image, status, strategy, deployed_by, reason, definition)
    VALUES (?, ?, ?, ?, 'complete', 'immediate', ?, ?, ?)
  `).run(releaseId, app.id, newVersion, targetRelease.image, req.userId, `Rollback to v${version}`, targetRelease.definition);

  db.conn.prepare("UPDATE apps SET current_release_id = ?, updated_at = datetime('now') WHERE id = ?").run(releaseId, app.id);
  db.conn.prepare("UPDATE machines SET image = ? WHERE app_id = ? AND status = 'running'").run(targetRelease.image, app.id);

  const release = db.conn.prepare('SELECT * FROM releases WHERE id = ?').get(releaseId);
  res.json({ ok: true, data: release, request_id: (res as any).requestId });
});
