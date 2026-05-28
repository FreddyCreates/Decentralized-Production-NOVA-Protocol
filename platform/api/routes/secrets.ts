import { Router } from 'express';
import { nanoid } from 'nanoid';
import { createHash } from 'crypto';
import { db } from '../db/index.js';
import { AuthRequest } from '../middleware/auth.js';

export const secretsRouter = Router();

// ─── List Secrets ────────────────────────────────────────────────────────────
secretsRouter.get('/:appName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  // Only return names and digests, never the values
  const secrets = db.conn.prepare(
    'SELECT name, digest, version, created_at FROM secrets WHERE app_id = ? ORDER BY name'
  ).all(app.id);

  res.json({ ok: true, data: secrets, request_id: (res as any).requestId });
});

// ─── Set Secrets ─────────────────────────────────────────────────────────────
secretsRouter.post('/:appName', (req: AuthRequest, res) => {
  const { secrets } = req.body;

  if (!secrets || typeof secrets !== 'object') {
    return res.status(400).json({ ok: false, error: 'secrets object required' });
  }

  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const results: { name: string; action: string }[] = [];

  for (const [name, value] of Object.entries(secrets)) {
    const digest = createHash('sha256').update(value as string).digest('hex').slice(0, 16);
    // In production this would be encrypted with the app's key
    const encrypted = Buffer.from(value as string).toString('base64');

    const existing = db.conn.prepare('SELECT * FROM secrets WHERE app_id = ? AND name = ?').get(app.id, name) as any;

    if (existing) {
      db.conn.prepare(
        "UPDATE secrets SET encrypted_value = ?, digest = ?, version = version + 1, created_at = datetime('now') WHERE app_id = ? AND name = ?"
      ).run(encrypted, digest, app.id, name);
      results.push({ name, action: 'updated' });
    } else {
      db.conn.prepare(
        'INSERT INTO secrets (id, app_id, name, encrypted_value, digest) VALUES (?, ?, ?, ?, ?)'
      ).run(`sec_${nanoid(16)}`, app.id, name, encrypted, digest);
      results.push({ name, action: 'created' });
    }
  }

  res.json({ ok: true, data: { set: results, deploy_needed: true }, request_id: (res as any).requestId });
});

// ─── Delete Secret ───────────────────────────────────────────────────────────
secretsRouter.delete('/:appName/:secretName', (req: AuthRequest, res) => {
  const app = db.conn.prepare('SELECT * FROM apps WHERE name = ? AND org_id = ?').get(req.params.appName, req.orgId) as any;
  if (!app) {
    return res.status(404).json({ ok: false, error: 'App not found' });
  }

  const result = db.conn.prepare('DELETE FROM secrets WHERE app_id = ? AND name = ?').run(app.id, req.params.secretName);
  if (result.changes === 0) {
    return res.status(404).json({ ok: false, error: 'Secret not found' });
  }

  res.json({ ok: true, data: { deleted: req.params.secretName }, request_id: (res as any).requestId });
});
