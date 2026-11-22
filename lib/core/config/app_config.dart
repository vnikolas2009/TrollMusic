abstract final class AppConfig {
  static const appName = 'TrollMusic';
  static const appVersion = '2.0.0';

  /// Vercel backend.
  static const defaultApiBase = String.fromEnvironment(
    'TROLL_API_BASE',
    defaultValue: 'https://trollmusic-plum.vercel.app',
  );

  static const connectTimeout = Duration(seconds: 10);
  static const requestTimeout = Duration(seconds: 20);
  static const playbackTimeout = Duration(seconds: 15);
  static const dohTimeout = Duration(seconds: 5);

  /// DoH JSON endpoints.
  ///
  /// Оба сервера поддерживают JSON-формат,
  /// который используется DohResolver.
  static const dohEndpoints = <String>[
    'https://dns.google/resolve',
    'https://cloudflare-dns.com/dns-query',
  ];

  static const soundcloudClientIdTtl = Duration(hours: 12);
  static const soundcloudStreamCacheTtl = Duration(minutes: 20);

  static const prefetchBefore = Duration(seconds: 15);

  static const coverCacheWidth = 600;
  static const thumbCacheWidth = 160;

  static const defaultHeaders = <String, String>{
    'user-agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  static const spotifyWebUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  static const audioBitrates = <int>[128, 192, 256, 320];
  static const defaultBitrate = 192;

  /// InnerTube client versions.
  static const androidVrVersion = '1.65.10';
  static const androidSdklessVersion = '20.10.38';
  static const ytMusicClientVersion = '1.20250310.01.00';

  static const spotifyQueries = <String>[
    'Top 50 Global',
    "Today's Top Hits",
    'Russian Top Hits',
    'RapCaviar',
  ];

  static const trendingQueries = <String>[
    'top hits 2026 official audio',
    'хиты 2026 русские песни',
    'new music friday',
    'billboard hot 100 songs',
    'трендовые песни топ чарт',
  ];
}