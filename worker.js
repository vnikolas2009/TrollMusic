/**
 * TrollMusic Cloudflare Worker — reverse proxy for Spotify API/CDN/embeds,
 * anonymous Spotify tokens, Piped/Invidious and audio passthrough.
 *
 * Routes:
 *   /spotify/*        -> https://api.spotify.com/*
 *   /accounts/*       -> https://accounts.spotify.com/*
 *   /cdn/*            -> https://i.scdn.co/*
 *   /embed/*          -> https://open.spotify.com/*
 *   /token            -> anonymous Spotify web-player token (cached)
 *   /piped/*          -> PIPED_ORIGIN (default https://pipedapi.adminforge.de)
 *   /invidious/*      -> INVIDIOUS_ORIGIN (default https://inv.nadeko.net)
 *   /proxy?url=...    -> whitelisted passthrough (audio stream, images, lrc)
 *
 * Vars/Secrets: PIPED_ORIGIN, INVIDIOUS_ORIGIN, ALLOWED_HOSTS, SPOTIFY_TOKEN
 */

const UPSTREAM = {
  spotify: 'https://api.spotify.com',
  accounts: 'https://accounts.spotify.com',
  cdn: 'https://i.scdn.co',
  embed: 'https://open.spotify.com',
};

const PASSTHROUGH_HOSTS = [
  'i.scdn.co',
  'image-cdn-ak.spotifycdn.com',
  'image-cdn-fa.spotifycdn.com',
  'mosaic.scdn.co',
  'thisis-images.scdn.co',
  'lineup-images.scdn.co',
  'seeded-session-images.scdn.co',
  'audio-ak-spotify-com.akamaized.net',
  'lrclib.net',
  'googlevideo.com',
  'ytimg.com',
];

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'access-control-allow-headers': '*',
  'access-control-expose-headers': 'content-length,content-type,accept-ranges,content-range',
};

const WEB_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...CORS },
  });

const withCors = (res) => {
  const out = new Response(res.body, res);
  Object.entries(CORS).forEach(([k, v]) => out.headers.set(k, v));
  return out;
};

const isAllowedHost = (host, env) => {
  const extra = (env.ALLOWED_HOSTS || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean);
  if (PASSTHROUGH_HOSTS.includes(host)) return true;
  if (host.includes('pipedproxy')) return true;
  if (host.endsWith('.googlevideo.com')) return true;
  return extra.includes(host);
};

const buildUpstreamHeaders = (request, env) => {
  const headers = new Headers();
  const auth = request.headers.get('authorization');
  if (auth) headers.set('authorization', auth);
  else if (env.SPOTIFY_TOKEN) headers.set('authorization', `Bearer ${env.SPOTIFY_TOKEN}`);
  const range = request.headers.get('range');
  if (range) headers.set('range', range);
  headers.set('user-agent', request.headers.get('user-agent') || WEB_UA);
  headers.set('accept-language', 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7');
  for (const name of [
    'accept',
    'content-type',
    'spotify-app-version',
    'app-platform',
    'origin',
    'referer',
    'if-none-match',
  ]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
};

async function forward(url, request, env) {
  const method = request.method === 'HEAD' ? 'HEAD' : request.method;
  const init = {
    method,
    headers: buildUpstreamHeaders(request, env),
    redirect: 'follow',
  };
  if (method !== 'GET' && method !== 'HEAD') init.body = await request.arrayBuffer();
  return fetch(url, init);
}

async function anonymousSpotifyToken(env) {
  const cache = caches.default;
  const cacheKey = new Request('https://trollmusic-proxy.internal/spotify-token');
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const endpoints = [
    'https://open.spotify.com/get_access_token?reason=transport&productType=web_player',
    'https://open.spotify.com/api/token?reason=init&productType=web_player',
  ];

  for (const endpoint of endpoints) {
    try {
      const res = await fetch(endpoint, {
        headers: {
          'user-agent': WEB_UA,
          accept: 'application/json, text/plain, */*',
          'accept-language': 'ru-RU,ru;q=0.9,en;q=0.8',
          'app-platform': 'WebPlayer',
          origin: 'https://open.spotify.com',
          referer: 'https://open.spotify.com/',
        },
      });
      if (!res.ok) continue;
      const data = await res.json();
      const token = data.accessToken || data.access_token;
      if (!token) continue;
      const output = new Response(JSON.stringify(data), {
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'public, max-age=3000',
          ...CORS,
        },
      });
      await cache.put(cacheKey, output.clone());
      return output;
    } catch (_) {
      // Пробуем следующий endpoint.
    }
  }
  return json({ error: 'spotify token unavailable' }, 502);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');

    try {
      if (path === '' || path === '/health') {
        return json({ ok: true, service: 'trollmusic-proxy' });
      }

      if (path === '/token') return await anonymousSpotifyToken(env);

      if (path === '/proxy') {
        const target = url.searchParams.get('url');
        if (!target) return json({ error: 'missing url' }, 400);
        const t = new URL(target);
        if (!isAllowedHost(t.hostname, env)) {
          return json({ error: `host not allowed: ${t.hostname}` }, 403);
        }
        return withCors(await forward(t.toString(), request, env));
      }

      const [, prefix, ...rest] = path.split('/');
      const tail = rest.join('/');
      const qs = url.search || '';

      if (prefix === 'spotify' || prefix === 'accounts' || prefix === 'cdn' || prefix === 'embed') {
        const base = UPSTREAM[prefix];
        const target = `${base}/${tail}${qs}`;
        return withCors(await forward(target, request, env));
      }

      if (prefix === 'piped' || prefix === 'invidious') {
        const base =
          prefix === 'piped'
            ? env.PIPED_ORIGIN || 'https://pipedapi.adminforge.de'
            : env.INVIDIOUS_ORIGIN || 'https://inv.nadeko.net';
        return withCors(await forward(`${base.replace(/\/$/, '')}/${tail}${qs}`, request, env));
      }

      return json({ error: 'unknown route' }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 502);
    }
  },
};
