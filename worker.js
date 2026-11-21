/**
 * TrollMusic Cloudflare Worker — reverse proxy for Spotify API/CDN/embeds,
 * anonymous Spotify tokens, Piped/Invidious and audio passthrough.
 *
 * Routes:
 *   /health[?deep=1]  -> worker status (deep also probes first mirrors)
 *   /spotify/*        -> https://api.spotify.com/*
 *   /accounts/*       -> https://accounts.spotify.com/*
 *   /cdn/*            -> https://i.scdn.co/*
 *   /embed/*          -> https://open.spotify.com/*
 *   /token            -> anonymous Spotify web-player token (cached)
 *   /piped/*          -> PIPED_ORIGIN (default https://pipedapi.adminforge.de)
 *   /piped/<host>/*   -> specific Piped mirror <host>
 *   /invidious/*      -> INVIDIOUS_ORIGIN (default https://inv.nadeko.net)
 *   /invidious/<host>/* -> specific Invidious mirror <host>
 *   /stream?v=<id>    -> resolve audio via Piped/Invidious and stream bytes
 *                        with Range support (CDN is fetched from the Worker,
 *                        so the client never talks to googlevideo directly)
 *   /proxy?url=...    -> whitelisted passthrough (audio stream, images, lrc)
 *
 * Vars/Secrets:
 *   PIPED_ORIGIN, PIPED_ORIGINS, INVIDIOUS_ORIGIN, INVIDIOUS_ORIGINS,
 *   ALLOWED_HOSTS, SPOTIFY_TOKEN, STREAM_FALLBACK (0/1, default 1)
 */

const UPSTREAM = {
  spotify: 'https://api.spotify.com',
  accounts: 'https://accounts.spotify.com',
  cdn: 'https://i.scdn.co',
  embed: 'https://open.spotify.com',
};

const DEFAULT_PIPED = [
  'https://pipedapi.adminforge.de',
  'https://pipedapi.reallyaweso.me',
  'https://pipedapi.ducks.party',
  'https://pipedapi.kavin.rocks',
  'https://api.piped.private.coffee',
];

const DEFAULT_INVIDIOUS = [
  'https://inv.nadeko.net',
  'https://invidious.nerdvpn.de',
  'https://yewtu.be',
  'https://inv.tux.pizza',
];

/// Хосты, которые разрешено запрашивать через /proxy и /stream.
/// Совпадение по суффиксу домена, а не по вхождению подстроки.
const PASSTHROUGH_SUFFIXES = [
  'i.scdn.co',
  'spotifycdn.com',
  'scdn.co',
  'lrclib.net',
  'googlevideo.com',
  'ytimg.com',
  'ggpht.com',
  'youtube.com',
  'pipedproxy',
];

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,HEAD,POST,PUT,DELETE,OPTIONS',
  'access-control-allow-headers': '*',
  'access-control-expose-headers':
    'content-length,content-type,accept-ranges,content-range,cache-control',
};

const WEB_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const AUDIO_UA =
  'com.google.android.youtube/19.44.38 (Linux; U; Android 11) gzip';

const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      ...CORS,
      ...extra,
    },
  });

const withCors = (res, extra = {}) => {
  const out = new Response(res.body, res);
  Object.entries({ ...CORS, ...extra }).forEach(([k, v]) => out.headers.set(k, v));
  return out;
};

const splitList = (value) =>
  (value || '')
    .split(/[,\s]+/)
    .map((h) => h.trim())
    .filter(Boolean);

const hostOf = (origin) => {
  try {
    return new URL(origin).host;
  } catch (_) {
    return '';
  }
};

/** Piped-зеркал может быть несколько: PIPED_ORIGINS важнее PIPED_ORIGIN. */
const pipedOrigins = (env) => {
  const list = splitList(env.PIPED_ORIGINS);
  if (list.length) return list;
  const single = splitList(env.PIPED_ORIGIN);
  if (single.length) return single;
  return DEFAULT_PIPED;
};

const invidiousOrigins = (env) => {
  const list = splitList(env.INVIDIOUS_ORIGINS);
  if (list.length) return list;
  const single = splitList(env.INVIDIOUS_ORIGIN);
  if (single.length) return single;
  return DEFAULT_INVIDIOUS;
};

const allowedHost = (host, env) => {
  if (!host) return false;
  const extra = splitList(env.ALLOWED_HOSTS);
  const all = [...PASSTHROUGH_SUFFIXES, ...extra];
  return all.some((suffix) => host === suffix || host.endsWith(`.${suffix}`));
};

const buildUpstreamHeaders = (request, env, ua = WEB_UA) => {
  const headers = new Headers();
  const auth = request.headers.get('authorization');
  if (auth) headers.set('authorization', auth);
  else if (env.SPOTIFY_TOKEN) headers.set('authorization', `Bearer ${env.SPOTIFY_TOKEN}`);
  const range = request.headers.get('range');
  if (range) headers.set('range', range);
  headers.set('user-agent', request.headers.get('user-agent') || ua);
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

const fetchTimeout = (url, init = {}, ms = 12000) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort('timeout'), ms);
  return fetch(url, { ...init, signal: controller.signal }).finally(() =>
    clearTimeout(timer),
  );
};

async function forward(url, request, env, ua) {
  const method = request.method === 'HEAD' ? 'HEAD' : request.method;
  const init = {
    method,
    headers: buildUpstreamHeaders(request, env, ua),
    redirect: 'follow',
  };
  if (method !== 'GET' && method !== 'HEAD') init.body = await request.arrayBuffer();
  return fetchTimeout(url, init);
}

/** Проксирование байтов аудио: Range/206 и заголовки апстрима сохраняются. */
async function proxyBytes(target, request, env, ua) {
  const method = request.method === 'HEAD' ? 'HEAD' : 'GET';
  const headers = new Headers();
  const range = request.headers.get('range');
  if (range) headers.set('range', range);
  headers.set('user-agent', ua);
  headers.set('accept', '*/*');
  headers.set('accept-language', 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7');
  headers.set('referer', 'https://www.youtube.com/');
  headers.set('origin', 'https://www.youtube.com');

  const upstream = await fetchTimeout(target, {
    method,
    headers,
    redirect: 'follow',
  });

  const out = new Headers({
    'content-type': upstream.headers.get('content-type') || 'audio/mp4',
    'cache-control': 'no-store',
    ...CORS,
  });
  for (const name of ['content-length', 'content-range', 'accept-ranges', 'etag']) {
    const value = upstream.headers.get(name);
    if (value) out.set(name, value);
  }
  if (!out.has('accept-ranges')) out.set('accept-ranges', 'bytes');
  return new Response(method === 'HEAD' ? null : upstream.body, {
    status: upstream.status,
    headers: out,
  });
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
      const res = await fetchTimeout(endpoint, {
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

/**
 * Резолв аудио через Piped/Invidious. Возвращает список кандидатов:
 * прямой googlevideo-URL и (если есть) proxyUrl зеркала.
 */
async function resolveAudioCandidates(videoId, env, preferredHost) {
  const allPiped = pipedOrigins(env);
  const ordered = preferredHost
    ? allPiped.filter((origin) => hostOf(origin) === preferredHost)
    : allPiped;
  const piped = ordered.length ? ordered : allPiped;

  for (const base of piped) {
    try {
      const res = await fetchTimeout(`${base.replace(/\/$/, '')}/streams/${videoId}`, {
        headers: { accept: 'application/json', 'user-agent': WEB_UA },
      });
      if (!res.ok) continue;
      const data = await res.json();
      const streams = (data.audioStreams || []).filter((s) => s && s.url);
      if (!streams.length) continue;
      streams.sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));
      const candidates = [];
      for (const stream of streams.slice(0, 2)) {
        if (stream.url) candidates.push(stream.url);
        if (stream.proxyUrl && stream.proxyUrl !== stream.url) {
          candidates.push(stream.proxyUrl);
        }
      }
      if (candidates.length) return { candidates, upstream: base };
    } catch (_) {
      // Следующее зеркало.
    }
  }

  const invidious = invidiousOrigins(env);
  const orderedInv = preferredHost
    ? invidious.filter((origin) => hostOf(origin) === preferredHost)
    : invidious;
  for (const base of orderedInv.length ? orderedInv : invidious) {
    try {
      const res = await fetchTimeout(`${base.replace(/\/$/, '')}/api/v1/videos/${videoId}`, {
        headers: { accept: 'application/json', 'user-agent': WEB_UA },
      });
      if (!res.ok) continue;
      const data = await res.json();
      const formats = (data.adaptiveFormats || []).filter(
        (f) => `${f.type || ''}`.startsWith('audio/') && f.url,
      );
      if (!formats.length) continue;
      formats.sort((a, b) => (parseInt(b.bitrate, 10) || 0) - (parseInt(a.bitrate, 10) || 0));
      const candidates = formats.slice(0, 2).map((f) => f.url);
      return { candidates, upstream: base };
    } catch (_) {
      // Следующее зеркало.
    }
  }
  return { candidates: [], upstream: null };
}

async function streamAudio(request, env, videoId, preferredHost) {
  const cache = caches.default;
  const urlKey = new Request(`https://trollmusic-proxy.internal/audio-url/${videoId}`);

  let candidates = [];
  const cached = await cache.match(urlKey);
  if (cached) {
    try {
      candidates = await cached.json();
    } catch (_) {
      candidates = [];
    }
  }
  if (!candidates.length) {
    const resolved = await resolveAudioCandidates(videoId, env, preferredHost);
    candidates = resolved.candidates;
    if (candidates.length) {
      await cache.put(
        urlKey,
        new Response(JSON.stringify(candidates), {
          headers: {
            'content-type': 'application/json',
            'cache-control': 'public, max-age=180',
          },
        }),
      );
    }
  }
  if (!candidates.length) {
    return json({ error: 'audio url not resolved', videoId }, 502);
  }

  let last = null;
  for (const target of candidates) {
    try {
      const host = hostOf(target);
      if (!allowedHost(host, env)) continue;
      const res = await proxyBytes(target, request, env, AUDIO_UA);
      if (res.status === 403 || res.status === 410 || res.status === 404) {
        last = res;
        continue;
      }
      return res;
    } catch (err) {
      last = err;
    }
  }
  if (last instanceof Response) return withCors(last);
  return json({ error: String(last || 'stream failed'), videoId }, 502);
}

async function health(env, deep) {
  const body = { ok: true, service: 'trollmusic-proxy', deep: Boolean(deep) };
  if (!deep) return json(body);

  const probe = async (base, path) => {
    const started = Date.now();
    try {
      const res = await fetchTimeout(`${base.replace(/\/$/, '')}${path}`, {
        headers: { accept: 'application/json', 'user-agent': WEB_UA },
      }, 5000);
      return { origin: base, ok: res.ok, status: res.status, ms: Date.now() - started };
    } catch (err) {
      return { origin: base, ok: false, status: 0, ms: Date.now() - started, error: String(err) };
    }
  };

  const piped = await Promise.all(
    pipedOrigins(env).slice(0, 3).map((base) => probe(base, '/trending?region=RU')),
  );
  const invidious = await Promise.all(
    invidiousOrigins(env).slice(0, 2).map((base) => probe(base, '/api/v1/trending?region=RU')),
  );
  body.piped = piped;
  body.invidious = invidious;
  body.ok = piped.some((p) => p.ok) || invidious.some((p) => p.ok);
  return json(body);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');

    try {
      if (path === '' || path === '/health') {
        return await health(env, url.searchParams.get('deep'));
      }

      if (path === '/token') return await anonymousSpotifyToken(env);

      if (path === '/stream') {
        const videoId = (url.searchParams.get('v') || url.searchParams.get('id') || '').trim();
        if (!/^[A-Za-z0-9_-]{6,20}$/.test(videoId)) {
          return json({ error: 'invalid video id' }, 400);
        }
        return await streamAudio(request, env, videoId, url.searchParams.get('host'));
      }

      if (path === '/proxy') {
        const target = url.searchParams.get('url');
        if (!target) return json({ error: 'missing url' }, 400);
        let parsed;
        try {
          parsed = new URL(target);
        } catch (_) {
          return json({ error: 'invalid url' }, 400);
        }
        if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
          return json({ error: 'unsupported scheme' }, 400);
        }
        if (!allowedHost(parsed.hostname, env)) {
          return json({ error: `host not allowed: ${parsed.hostname}` }, 403);
        }
        return withCors(await forward(parsed.toString(), request, env));
      }

      const [, prefix, ...rest] = path.split('/');
      const tail = rest.join('/');
      const qs = url.search || '';

      if (prefix === 'spotify' || prefix === 'accounts' || prefix === 'cdn' || prefix === 'embed') {
        const base = UPSTREAM[prefix];
        return withCors(await forward(`${base}/${tail}${qs}`, request, env));
      }

      if (prefix === 'piped' || prefix === 'invidious') {
        const parts = tail.split('/');
        const first = parts[0] || '';
        // /piped/<host>/path, если первый сегмент похож на хост (есть точка),
        // иначе — /piped/path на первое зеркало из конфигурации.
        const explicit = first.includes('.') && !first.includes('?');
        const host = explicit ? first : null;
        const restPath = explicit ? parts.slice(1).join('/') : tail;
        const list = prefix === 'piped' ? pipedOrigins(env) : invidiousOrigins(env);
        const base = host ? `https://${host}` : list[0];
        if (!base) return json({ error: 'no upstream configured' }, 500);
        return withCors(await forward(`${base.replace(/\/$/, '')}/${restPath}${qs}`, request, env));
      }

      return json({ error: 'unknown route' }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 502);
    }
  },
};
