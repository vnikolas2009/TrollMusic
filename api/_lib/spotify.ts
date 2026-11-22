const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/124.0.0.0 Safari/537.36';

const SPOTIFY_ORIGIN = 'https://api.spotify.com';
const TOKEN_URL =
  'https://open.spotify.com/get_access_token' +
  '?reason=transport&productType=web_player';

const REQUEST_TIMEOUT = 12000;
const MAX_TRACKS = 1000;
const MAX_PAGES = 20;

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

export async function getAnonymousToken(
  force = false,
): Promise<SpotifyToken> {
  const now = Date.now();

  if (
    !force &&
    cached &&
    cached.expiresAt - 30_000 > now
  ) {
    return cached;
  }

  if (!force && inflight) {
    return inflight;
  }

  const request = (async (): Promise<SpotifyToken> => {
    const response = await fetch(TOKEN_URL, {
      method: 'GET',
      headers: {
        'User-Agent': UA,
        Accept: 'application/json',
        'App-Platform': 'WebPlayer',
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT),
    });

    if (!response.ok) {
      throw new Error(
        `Spotify token HTTP ${response.status}`,
      );
    }

    const data = (await response.json()) as {
      accessToken?: string;
      accessTokenExpirationTimestampMs?: number;
    };

    const accessToken = data.accessToken;

    if (
      typeof accessToken !== 'string' ||
      accessToken.length === 0
    ) {
      throw new Error('Spotify token missing');
    }

    const expiration =
      Number(data.accessTokenExpirationTimestampMs) ||
      Date.now() + 50 * 60_000;

    if (expiration <= Date.now()) {
      throw new Error('Spotify returned expired token');
    }

    const result: SpotifyToken = {
      accessToken,
      expiresAt: expiration,
    };

    cached = result;

    return result;
  })();

  inflight = request;

  try {
    return await request;
  } finally {
    if (inflight === request) {
      inflight = null;
    }
  }
}

async function api<T>(
  path: string,
  token: string,
): Promise<T> {
  const response = await fetch(
    `${SPOTIFY_ORIGIN}/v1${path}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'User-Agent': UA,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT),
    },
  );

  if (response.status === 401) {
    throw new Error('unauthorized');
  }

  if (!response.ok) {
    throw new Error(
      `Spotify API HTTP ${response.status}`,
    );
  }

  return (await response.json()) as T;
}

type SpotifyArtist = {
  name?: string;
};

type SpotifyImage = {
  url?: string;
};

type SpotifyTrack = {
  id?: string;
  name?: string;
  duration_ms?: number;
  artists?: SpotifyArtist[];
  album?: {
    images?: SpotifyImage[];
  };
};

type SpotifyPage = {
  items?: Array<{
    track?: SpotifyTrack | null;
  }>;
  next?: string | null;
};

function mapTrack(
  track: SpotifyTrack | null | undefined,
  fallbackCover: string | null,
): TrackMeta | null {
  if (
    !track ||
    typeof track.id !== 'string' ||
    typeof track.name !== 'string'
  ) {
    return null;
  }

  const cover =
    track.album?.images?.[0]?.url ??
    fallbackCover;

  return {
    id: track.id,
    title: track.name,
    artist: (track.artists ?? [])
      .map((artist) => artist.name ?? '')
      .filter(Boolean)
      .join(', '),
    durationMs: Number(track.duration_ms ?? 0),
    cover: cover ?? null,
  };
}

async function fetchUrl(
  url: string,
  token: string,
): Promise<unknown> {
  const parsed = new URL(url);

  if (
    parsed.protocol !== 'https:' ||
    parsed.hostname !== 'api.spotify.com'
  ) {
    throw new Error('Invalid Spotify pagination URL');
  }

  const response = await fetch(parsed, {
    headers: {
      Authorization: `Bearer ${token}`,
      'User-Agent': UA,
      Accept: 'application/json',
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT),
  });

  if (response.status === 401) {
    throw new Error('unauthorized');
  }

  if (!response.ok) {
    throw new Error(
      `Spotify pagination HTTP ${response.status}`,
    );
  }

  return response.json();
}

async function paged(
  first: SpotifyPage,
  token: string,
  fallbackCover: string | null,
): Promise<TrackMeta[]> {
  const out: TrackMeta[] = [];

  let page: SpotifyPage | null = first;

  let guard = 0;

  while (
    page &&
    guard++ < MAX_PAGES &&
    out.length < MAX_TRACKS
  ) {
    for (const item of page.items ?? []) {
      const track = mapTrack(
        item.track,
        fallbackCover,
      );

      if (track) {
        out.push(track);
      }

      if (out.length >= MAX_TRACKS) break;
    }

    if (!page.next || out.length >= MAX_TRACKS) {
      break;
    }

    page = await fetchUrl(
      page.next,
      token,
    ) as SpotifyPage;
  }

  return out;
}

export async function importMeta(
  type: string,
  id: string,
): Promise<ImportResult> {
  if (!['playlist', 'album', 'track'].includes(type)) {
    throw new Error('Unsupported Spotify resource');
  }

  let token = await getAnonymousToken();

  const run = async (
    accessToken: string,
  ): Promise<ImportResult> => {
    if (type === 'track') {
      const track = await api<SpotifyTrack>(
        `/tracks/${id}`,
        accessToken,
      );

      const mapped = mapTrack(track, null);

      if (!mapped) {
        throw new Error('Spotify track not found');
      }

      return {
        type: 'track',
        id,
        title: mapped.title,
        cover: mapped.cover,
        tracks: [mapped],
      };
    }

    if (type === 'album') {
      const album = await api<{
        id?: string;
        name?: string;
        images?: SpotifyImage[];
        artists?: SpotifyArtist[];
        tracks?: SpotifyPage;
      }>(
        `/albums/${id}`,
        accessToken,
      );

      const cover =
        album.images?.[0]?.url ?? null;

      const albumArtist = (album.artists ?? [])
        .map((artist) => artist.name ?? '')
        .filter(Boolean)
        .join(', ');

      const items = (album.tracks?.items ?? []).map(
        (item) => ({
          track: {
            ...item.track,
            album: {
              images: album.images,
            },
          },
        }),
      );

      const tracks = await paged(
        {
          items,
          next: album.tracks?.next,
        },
        accessToken,
        cover,
      );

      return {
        type: 'album',
        id,
        title: album.name ?? 'Альбом',
        cover,
        tracks: tracks.map((track) => ({
          ...track,
          artist: track.artist || albumArtist,
        })),
      };
    }

    const playlist = await api<{
      id?: string;
      name?: string;
      images?: SpotifyImage[];
      tracks?: SpotifyPage;
    }>(
      `/playlists/${id}` +
        '?fields=name,images,' +
        'tracks(items(track(id,name,duration_ms,' +
        'artists(name),album(images))),next)',
      accessToken,
    );

    const cover =
      playlist.images?.[0]?.url ?? null;

    const tracks = await paged(
      playlist.tracks ?? {},
      accessToken,
      cover,
    );

    return {
      type: 'playlist',
      id,
      title: playlist.name ?? 'Плейлист',
      cover,
      tracks,
    };
  };

  try {
    return await run(token.accessToken);
  } catch (error) {
    if ((error as Error).message !== 'unauthorized') {
      throw error;
    }

    token = await getAnonymousToken(true);

    return run(token.accessToken);
  }
}