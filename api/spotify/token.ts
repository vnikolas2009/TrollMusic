import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getAnonymousToken } from '../_lib/spotify';

export default async function handler(_req: VercelRequest, res: VercelResponse) {
  try {
    const t = await getAnonymousToken();
    res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');
    res.status(200).json({ accessToken: t.accessToken, expiresAt: t.expiresAt });
  } catch (e) {
    res.status(502).json({ error: (e as Error).message });
  }
}
