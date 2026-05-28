import { Request, Response, NextFunction } from 'express';
import { nanoid } from 'nanoid';

export function requestId(req: Request, res: Response, next: NextFunction) {
  const id = nanoid(12);
  (res as any).requestId = id;
  res.setHeader('X-Request-Id', id);
  next();
}
