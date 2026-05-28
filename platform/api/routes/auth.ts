import { Router } from 'express';
import { nanoid } from 'nanoid';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { db } from '../db/index.js';
import { JWT_SECRET } from '../middleware/auth.js';

export const authRouter = Router();

// ─── Sign Up ─────────────────────────────────────────────────────────────────
authRouter.post('/signup', async (req, res) => {
  const { email, password, name } = req.body;

  if (!email || !password) {
    return res.status(400).json({ ok: false, error: 'email and password required' });
  }

  const existing = db.conn.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (existing) {
    return res.status(409).json({ ok: false, error: 'User already exists' });
  }

  const userId = `usr_${nanoid(16)}`;
  const orgId = `org_${nanoid(16)}`;
  const orgSlug = email.split('@')[0].toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const passwordHash = await bcrypt.hash(password, 12);
  const apiToken = `nova_${nanoid(32)}`;

  db.conn.prepare('INSERT INTO organizations (id, name, slug, type) VALUES (?, ?, ?, ?)').run(
    orgId, name || orgSlug, orgSlug, 'personal'
  );

  db.conn.prepare('INSERT INTO users (id, email, password_hash, name, org_id, api_token) VALUES (?, ?, ?, ?, ?, ?)').run(
    userId, email, passwordHash, name || '', orgId, apiToken
  );

  const token = jwt.sign({ sub: userId, org: orgId, email }, JWT_SECRET, { expiresIn: '30d' });

  res.status(201).json({
    ok: true,
    data: {
      user_id: userId,
      org_id: orgId,
      token,
      api_token: apiToken,
    },
  });
});

// ─── Login ───────────────────────────────────────────────────────────────────
authRouter.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ ok: false, error: 'email and password required' });
  }

  const user = db.conn.prepare('SELECT * FROM users WHERE email = ?').get(email) as any;
  if (!user) {
    return res.status(401).json({ ok: false, error: 'Invalid credentials' });
  }

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    return res.status(401).json({ ok: false, error: 'Invalid credentials' });
  }

  const token = jwt.sign({ sub: user.id, org: user.org_id, email }, JWT_SECRET, { expiresIn: '30d' });

  res.json({
    ok: true,
    data: {
      user_id: user.id,
      org_id: user.org_id,
      token,
      api_token: user.api_token,
    },
  });
});

// ─── Token Info ──────────────────────────────────────────────────────────────
authRouter.get('/tokens', (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ ok: false, error: 'Not authenticated' });
  }

  const token = authHeader.slice(7);
  const user = db.conn.prepare('SELECT id, email, name, org_id, api_token, created_at FROM users WHERE api_token = ?').get(token) as any;
  if (user) {
    return res.json({ ok: true, data: user });
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET) as any;
    const u = db.conn.prepare('SELECT id, email, name, org_id, api_token, created_at FROM users WHERE id = ?').get(payload.sub) as any;
    return res.json({ ok: true, data: u });
  } catch {
    return res.status(401).json({ ok: false, error: 'Invalid token' });
  }
});
