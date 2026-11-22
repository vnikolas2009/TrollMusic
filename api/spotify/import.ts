import type { VercelRequest, VercelResponse } from '@vercel/node';
import { importMeta } from '../_lib/spotify';

const ID = /^[A-Za-z0-9]{10,32}$/;
const TYPES = new Set(['playlist', 'album', 'track']);

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const type = String(req.query.type ?? '');
  const id = String(req.query.id ?? '');
  if (!TYPES.has(type) || !ID.test(id)) {
    res.status(400).json({ error: 'bad type or id' });
    return;
  }
  try {
    const r = await importMeta(type, id);
    res.setHeader('Cache-Control', 's-maxage=600, stale-while-revalidate=3600');
    res.status(200).json(r);
  } catch (e) {
    res.status(502).json({ error: (e as Error).message });
  }
}
