abstract final class AppConfig {
  static const appName = 'TrollMusic';
  static const appVersion = '1.1.0';
  /// Публичного Worker нет: пользователь разворачивает свой (см. README).
  /// Адрес встроенного Worker подставляется при сборке (`--dart-define=WORKER_URL=...`).
  static const defaultWorkerUrl = String.fromEnvironment('WORKER_URL');
  static const mirrorTimeout = Duration(seconds: 4);
  static const requestTimeout = Duration(seconds: 20);
  static const playbackTimeout = Duration(seconds: 12);

  /// Заголовки, максимально похожие на обычный клиент. Помогают обходить
  /// часть гео/бот-ограничений без пользовательского OAuth.
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

  static const defaultPipedInstances = <String>[
    'https://pipedapi.adminforge.de',
    'https://pipedapi.reallyaweso.me',
    'https://pipedapi.ducks.party',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.leptons.xyz',
    'https://api.piped.private.coffee',
    'https://pipedapi.nosebs.ru',
  ];

  static const defaultInvidiousInstances = <String>[
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yewtu.be',
    'https://inv.tux.pizza',
    'https://invidious.privacyredirect.com',
    'https://iv.ggtyler.dev',
    'https://invidious.f5.si',
  ];

  static const audioBitrates = <int>[128, 192, 256, 320];
  static const defaultBitrate = 192;

  /// Каталоги публичных инстансов: приложение обновляет списки само.
  static const pipedDirectoryUrl = 'https://piped-instances.kavin.rocks/';
  static const invidiousDirectoryUrl =
      'https://api.invidious.io/instances.json?sort_by=type,health';

  /// Версии клиентов InnerTube. Если YouTube перестанет их принимать,
  /// достаточно обновить значения здесь.
  static const androidVrVersion = '1.65.10';
  static const androidSdklessVersion = '20.10.38';
  static const ytMusicClientVersion = '1.20250310.01.00';

  /// User-Agent для потоков, полученных через Piped/Invidious.
  static const genericAudioUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// Запросы для блока «Популярное в Spotify».
  static const spotifyQueries = <String>[
    'Top 50 Global',
    'Today\'s Top Hits',
    'Russian Top Hits',
    'RapCaviar',
  ];

  /// Запросы для блока «Популярная музыка» на главной (только музыка).
  static const trendingQueries = <String>[
    'top hits 2026 official audio',
    'хиты 2026 русские песни',
    'new music friday',
    'billboard hot 100 songs',
    'трендовые песни топ чарт',
  ];
}
