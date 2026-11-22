import type {
  VercelRequest,
  VercelResponse,
} from '@vercel/node';

import {
  importMeta,
} from '../_lib/spotify';

const ID = /^[A-Za-z0-9]{10,32}$/;

const TYPES = new Set([
  'playlist',
  'album',
  'track',
]);

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
) {
  res.setHeader(
    'Access-Control-Allow-Origin',
    '*',
  );

  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');

    res.status(405).json({
      error: 'Method not allowed',
    });

    return;
  }

  const type = String(req.query.type ?? '');
  const id = String(req.query.id ?? '');

  if (!TYPES.has(type) || !ID.test(id)) {
    res.status(400).json({
      error: 'Invalid Spotify type or ID',
    });

    return;
  }

  try {
    const result = await importMeta(
      type,
      id,
    );

    res.setHeader(
      'Cache-Control',
      'public, s-maxage=600, stale-while-revalidate=3600',
    );

    res.status(200).json(result);
  } catch (error) {
    console.error(
      'Spotify import error:',
      error,
    );

    res.status(502).json({
      error: 'Spotify import failed',
    });
  }
}