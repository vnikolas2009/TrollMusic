import type {
  VercelRequest,
  VercelResponse,
} from '@vercel/node';

import {
  getAnonymousToken,
} from '../_lib/spotify';

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
) {
  res.setHeader(
    'Cache-Control',
    'no-store, max-age=0',
  );

  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    res.status(405).json({
      error: 'Method not allowed',
    });
    return;
  }

  try {
    const token = await getAnonymousToken();

    res.status(200).json({
      accessToken: token.accessToken,
      expiresAt: token.expiresAt,
    });
  } catch (error) {
    console.error(
      'Spotify token error:',
      error,
    );

    res.status(502).json({
      error: 'Spotify token unavailable',
    });
  }
}