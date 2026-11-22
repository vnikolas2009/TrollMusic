abstract final class AppConfig {
  static const appName = 'TrollMusic';
  static const appVersion = '2.0.0';

  /// Базовый URL своего Vercel-деплоя (`/api/spotify/*`). Переопределяется
  /// в настройках или через `--dart-define=TROLL_API_BASE=https://...`.
  static const defaultApiBase = String.fromEnvironment(
    'TROLL_API_BASE',
    defaultValue: 'https://trollmusic.vercel.app',
  );

  static const connectTimeout = Duration(seconds: 8);
  static const requestTimeout = Duration(seconds: 20);
  static const playbackTimeout = Duration(seconds: 12);

  /// DNS-over-HTTPS: запросы идут на IP-адреса, поэтому системный DNS
  /// (и его подмена у провайдера) не участвует.
  static const dohEndpoints = <String>[
    'https://8.8.8.8/resolve',
    'https://9.9.9.9:5053/dns-query',
  ];
  static const dohTimeout = Duration(seconds: 4);

  /// Время жизни `client_id` SoundCloud в кэше.
  static const soundcloudClientIdTtl = Duration(hours: 24);

  /// За сколько до конца трека резолвится следующий.
  static const prefetchBefore = Duration(seconds: 15);

  /// Ширина декодирования обложек (логические пиксели × DPR считает виджет).
  static const coverCacheWidth = 600;
  static const thumbCacheWidth = 160;

  /// Заголовки, максимально похожие на обычный клиент.
  static const defaultHeaders = <String, String>{
    'user-agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  static const spotifyWebUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const audioBitrates = <int>[128, 192, 256, 320];
  static const defaultBitrate = 192;
}
