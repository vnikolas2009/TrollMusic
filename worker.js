/**
 * YSPlayer Cloudflare Worker — reverse proxy for Spotify API/CDN and embeds.
 *
 * Routes:
 *   /spotify/*        -> https://api.spotify.com/*
 *   /cdn/*            -> https://i.scdn.co/*
 *   /embed/*          -> https://open.spotify.com/*
 *   /piped/*          -> PIPED_ORIGIN (default https://pipedapi.kavin.rocks)
 *   /invidious/*      -> INVIDIOUS_ORIGIN (default https://inv.nadeko.net)
 *   /proxy?url=...    -> whitelisted passthrough (audio stream, images, lrc)
 *
 * Secrets/vars: PIPED_ORIGIN, INVIDIOUS_ORIGIN, ALLOWED_ORIGINS, SPOTIFY_TOKEN
 */

const UPSTREAM = {
  spotify: 'https://api.spotify.com',
  cdn: 'https://i.scdn.co',
  embed: 'https://open.spotify.com',
};

const PASSTHROUGH_HOSTS = [
  'i.scdn.co',
  'image-cdn-ak.spotifycdn.com',
  'image-cdn-fa.spotifycdn.com',
  'mosaic.scdn.co',
  'lrclib.net',
  'pipedproxy',
  'googlevideo.com',
  'ytimg.com',
];

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'access-control-allow-headers': '*',
  'access-control-expose-headers': 'content-length,content-type,accept-ranges,content-range',
};

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
  const extra = (env.ALLOWED_HOSTS || '').split(',').map((h) => h.trim()).filter(Boolean);
  if (PASSTHROUGH_HOSTS.includes(host)) return true;
  if (host.endsWith('.pipedproxy') || host.includes('pipedproxy')) return true;
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
  const ua = request.headers.get('user-agent');
  headers.set('user-agent', ua || 'YSPlayer/0.1 (+https://github.com/vnikolas2009/YSPlayer)');
  const accept = request.headers.get('accept');
  if (accept) headers.set('accept', accept);
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

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');

    try {
      if (path === '' || path === '/health') return json({ ok: true, service: 'ysplayer-proxy' });

      if (path === '/proxy') {
        const target = url.searchParams.get('url');
        if (!target) return json({ error: 'missing url' }, 400);
        const t = new URL(target);
        if (!isAllowedHost(t.hostname, env)) return json({ error: `host not allowed: ${t.hostname}` }, 403);
        return withCors(await forward(t.toString(), request, env));
      }

      const [, prefix, ...rest] = path.split('/');
      const tail = rest.join('/');
      const qs = url.search ? url.search : '';

      if (prefix === 'spotify' || prefix === 'cdn' || prefix === 'embed') {
        const base = UPSTREAM[prefix];
        const target = `${base}/${tail}${qs}`;
        return withCors(await forward(target, request, env));
      }

      if (prefix === 'piped' || prefix === 'invidious') {
        const base = prefix === 'piped'
          ? (env.PIPED_ORIGIN || 'https://pipedapi.kavin.rocks')
          : (env.INVIDIOUS_ORIGIN || 'https://inv.nadeko.net');
        return withCors(await forward(`${base.replace(/\/$/, '')}/${tail}${qs}`, request, env));
      }

      return json({ error: 'unknown route' }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 502);
    }
  },
};
