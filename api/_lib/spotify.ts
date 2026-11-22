const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

export interface SpotifyToken {
  accessToken: string;
  expiresAt: number;
}

export interface TrackMeta {
  id: string;
  title: string;
  artist: string;
  durationMs: number;
  cover: string | null;
}

export interface ImportResult {
  type: 'playlist' | 'album' | 'track';
  id: string;
  title: string;
  cover: string | null;
  tracks: TrackMeta[];
}

let cached: SpotifyToken | null = null;
let inflight: Promise<SpotifyToken> | null = null;

export async function getAnonymousToken(force = false): Promise<SpotifyToken> {
  const now = Date.now();
  if (!force && cached && cached.expiresAt - 30_000 > now) return cached;
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const res = await fetch(
        'https://open.spotify.com/get_access_token?reason=transport&productType=web_player',
        { headers: { 'User-Agent': UA, Accept: 'application/json', 'App-Platform': 'WebPlayer' } },
      );
      if (!res.ok) throw new Error(`spotify token ${res.status}`);
      const j = (await res.json()) as {
        accessToken?: string;
        accessTokenExpirationTimestampMs?: number;
      };
      if (!j.accessToken) throw new Error('spotify token missing');
      cached = {
        accessToken: j.accessToken,
        expiresAt: j.accessTokenExpirationTimestampMs ?? now + 50 * 60_000,
      };
      return cached;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}

async function api<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`https://api.spotify.com/v1${path}`, {
    headers: { Authorization: `Bearer ${token}`, 'User-Agent': UA },
  });
  if (res.status === 401) throw new Error('unauthorized');
  if (!res.ok) throw new Error(`spotify api ${res.status}`);
  return (await res.json()) as T;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
function mapTrack(t: any, fallbackCover: string | null): TrackMeta | null {
  if (!t || !t.id || !t.name) return null;
  const images: any[] = t.album?.images ?? [];
  return {
    id: String(t.id),
    title: String(t.name),
    artist: (t.artists ?? []).map((a: any) => a.name).join(', '),
    durationMs: Number(t.duration_ms ?? 0),
    cover: images[0]?.url ?? fallbackCover,
  };
}

async function paged(first: any, token: string, fallbackCover: string | null) {
  const out: TrackMeta[] = [];
  let page = first;
  while (page) {
    for (const it of page.items ?? []) {
      const m = mapTrack(it.track ?? it, fallbackCover);
      if (m) out.push(m);
    }
    page = page.next ? await fetchUrl(page.next, token) : null;
    if (out.length > 1000) break;
  }
  return out;
}

async function fetchUrl(url: string, token: string): Promise<any> {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}`, 'User-Agent': UA } });
  if (!res.ok) throw new Error(`spotify api ${res.status}`);
  return res.json();
}

export async function importMeta(type: string, id: string): Promise<ImportResult> {
  let tok = await getAnonymousToken();
  const run = async (token: string): Promise<ImportResult> => {
    if (type === 'track') {
      const t = await api<any>(`/tracks/${id}`, token);
      const m = mapTrack(t, null);
      if (!m) throw new Error('track not found');
      return { type: 'track', id, title: m.title, cover: m.cover, tracks: [m] };
    }
    if (type === 'album') {
      const a = await api<any>(`/albums/${id}`, token);
      const cover: string | null = a.images?.[0]?.url ?? null;
      const items = (a.tracks?.items ?? []).map((t: any) => ({ ...t, album: { images: a.images } }));
      const tracks = await paged({ items, next: a.tracks?.next }, token, cover);
      return { type: 'album', id, title: String(a.name ?? ''), cover, tracks };
    }
    const p = await api<any>(`/playlists/${id}?fields=name,images,tracks(items(track(id,name,duration_ms,artists(name),album(images))),next)`, token);
    const cover: string | null = p.images?.[0]?.url ?? null;
    const tracks = await paged(p.tracks, token, cover);
    return { type: 'playlist', id, title: String(p.name ?? ''), cover, tracks };
  };
  try {
    return await run(tok.accessToken);
  } catch (e) {
    if ((e as Error).message !== 'unauthorized') throw e;
    tok = await getAnonymousToken(true);
    return run(tok.accessToken);
  }
}
