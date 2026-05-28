import { Router } from 'express';
import { DEFAULT_REGIONS } from '../../shared/types.js';

export const regionsRouter = Router();

// ─── List Regions ────────────────────────────────────────────────────────────
regionsRouter.get('/', (_req, res) => {
  res.json({ ok: true, data: DEFAULT_REGIONS, request_id: (res as any).requestId });
});
