import type { Response } from 'express';

export interface PageMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export function sendData<T>(res: Response, data: T, status = 200): void {
  res.status(status).json({ data });
}

export function sendPage<T>(res: Response, items: T[], meta: Omit<PageMeta, 'totalPages'>): void {
  res.status(200).json({
    data: items,
    meta: { ...meta, totalPages: Math.max(1, Math.ceil(meta.total / meta.limit)) },
  });
}

export function sendNoContent(res: Response): void {
  res.status(204).end();
}
