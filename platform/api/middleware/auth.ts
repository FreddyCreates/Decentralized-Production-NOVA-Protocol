import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { db } from '../db/index.js';

const JWT_SECRET = process.env.NOVA_JWT_SECRET || 'nova-sovereign-dev-secret';

export interface AuthRequest extends Request {
  userId?: string;
  orgId?: string;
}

export function authMiddleware(req: AuthRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return res.status(401).json({ ok: false, error: 'Authorization header required' });
  }

  // Support both ****** (JWT) and token-based (API key)
  if (authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7);

    // Check if it's an API token first
    const user = db.conn.prepare('SELECT id, org_id FROM users WHERE api_token = ?').get(token) as any;
    if (user) {
      req.userId = user.id;
      req.orgId = user.org_id;
      return next();
    }

    // Try JWT
    try {
      const payload = jwt.verify(token, JWT_SECRET) as any;
      req.userId = payload.sub;
      req.orgId = payload.org;
      return next();
    } catch {
      return res.status(401).json({ ok: false, error: 'Invalid token' });
    }
  }

  return res.status(401).json({ ok: false, error: 'Invalid authorization format' });
}

export { JWT_SECRET };
