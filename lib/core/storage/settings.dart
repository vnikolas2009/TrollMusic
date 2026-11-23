import 'package:hive_flutter/hive_flutter.dart';

import '../config/app_config.dart';
import '../utils/audio_pick.dart';

class Settings {
  Settings(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  static Future<Settings> open() async {
    final box = await Hive.openBox<dynamic>(boxName);
    return Settings(box);
  }

  /// Базовый URL Vercel-бэкенда с метаданными Spotify.
  String get apiBaseUrl {
    final raw = (_box.get('apiBaseUrl') as String? ?? '').trim();
    final value = raw.isEmpty ? AppConfig.defaultApiBase : raw;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  set apiBaseUrl(String value) => _box.put('apiBaseUrl', value.trim());

  /// HTTP-прокси для всех соединений приложения (пусто — напрямую).
  String get httpProxy => (_box.get('httpProxy') as String? ?? '').trim();

  set httpProxy(String value) => _box.put('httpProxy', value.trim());

  /// Использовать системные настройки прокси (переменные окружения / ОС).
  bool get useSystemProxy =>
      _box.get('useSystemProxy', defaultValue: true) as bool;

  set useSystemProxy(bool value) => _box.put('useSystemProxy', value);

  /// Дополнительные заголовки, по одному на строку: `Name: value`.
  String get customHeaders => _box.get('customHeaders') as String? ?? '';

  set customHeaders(String value) => _box.put('customHeaders', value);

  Map<String, String> get requestHeaders {
    final headers = <String, String>{};
    for (final line in customHeaders.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final name = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) headers[name] = value;
    }
    return headers;
  }

  /// Гостевой режим Spotify: анонимный веб-токен + публичные метаданные.
  bool get spotifyGuestMode =>
      _box.get('spotifyGuestMode', defaultValue: true) as bool;

  set spotifyGuestMode(bool value) => _box.put('spotifyGuestMode', value);

  /// Пользовательский Bearer-токен Spotify (необязательно).
  String get spotifyAccessToken =>
      _box.get('spotifyAccessToken') as String? ?? '';

  set spotifyAccessToken(String value) =>
      _box.put('spotifyAccessToken', value.trim());

  String get spotifyClientId => _box.get('spotifyClientId') as String? ?? '';

  set spotifyClientId(String value) => _box.put('spotifyClientId', value.trim());

  String get spotifyClientSecret =>
      _box.get('spotifyClientSecret') as String? ?? '';

  set spotifyClientSecret(String value) =>
      _box.put('spotifyClientSecret', value.trim());

  /// OAuth-токен Яндекс Музыки пользователя (необязателен: без него поиск
  /// и чарты работают, а звук подбирается на других источниках).
  String get yandexToken => (_box.get('yandexToken') as String? ?? '').trim();

  set yandexToken(String value) => _box.put('yandexToken', value.trim());

  /// Токен пользователя для VK API (`audio.*`). Без него VK Музыка недоступна.
  /// Клиентский токен Genius (genius.com/api-clients) для поиска текстов.
  String get geniusToken => (_box.get('geniusToken') as String? ?? '').trim();

  set geniusToken(String value) => _box.put('geniusToken', value.trim());

  String get vkToken => (_box.get('vkToken') as String? ?? '').trim();

  set vkToken(String value) => _box.put('vkToken', value.trim());

  // ---------------------------------------------------------------- звук

  /// Качество звука: Низкое / Среднее / Высокое / Авто (по умолчанию Авто).
  AudioQuality get audioQuality {
    final index = (_box.get('audioQuality') as num?)?.toInt() ?? AudioQuality.auto.index;
    return AudioQuality.values[index.clamp(0, AudioQuality.values.length - 1)];
  }

  set audioQuality(AudioQuality value) => _box.put('audioQuality', value.index);

  /// Целевой битрейт потока (производная от качества).
  int get bitrate {
    switch (audioQuality) {
      case AudioQuality.low:
        return 64;
      case AudioQuality.medium:
        return 128;
      case AudioQuality.high:
      case AudioQuality.auto:
        return 256;
    }
  }

  /// Opus не поддерживается AVPlayer, поэтому предпочитаем AAC.
  bool get preferOpus => false;

  /// Подготавливать следующий трек заранее, чтобы переход был без пауз.
  bool get gaplessEnabled => _box.get('gapless', defaultValue: true) as bool;

  set gaplessEnabled(bool value) => _box.put('gapless', value);

  /// Выравнивать громкость треков по данным YouTube (`loudnessDb`).
  bool get normalizeVolume => _box.get('normalizeVolume', defaultValue: true) as bool;

  set normalizeVolume(bool value) => _box.put('normalizeVolume', value);

  // ----------------------------------------------------------------- тема

  /// 0 — системная, 1 — светлая, 2 — тёмная (порядок `ThemeMode`).
  /// Выбранный источник каталога: 0 — Spotify, 1 — YouTube Music (по умолчанию: работает без бэкенда).
  int get musicSourceIndex => (_box.get('musicSource', defaultValue: 1) as num).toInt();

  set musicSourceIndex(int value) => _box.put('musicSource', value);

  int get themeModeIndex =>
      ((_box.get('themeMode') as num?)?.toInt() ?? 2).clamp(0, 2);

  set themeModeIndex(int value) => _box.put('themeMode', value);

  int get accentValue => (_box.get('accentValue') as num?)?.toInt() ?? 0xFF1ED760;

  set accentValue(int value) => _box.put('accentValue', value);

  /// Чисто чёрный фон в тёмной теме (экономит батарею на OLED).
  bool get amoled => _box.get('amoled', defaultValue: false) as bool;

  set amoled(bool value) => _box.put('amoled', value);

  /// Лёгкий градиент от акцентного цвета в верхней части экранов.
  bool get gradientBackground =>
      _box.get('gradientBackground', defaultValue: true) as bool;

  set gradientBackground(bool value) => _box.put('gradientBackground', value);

  // ------------------------------------------------------------- матчи

  /// Соответствие Spotify-трека видео на YouTube (сохраняется между запусками).
  String? matchedVideo(String spotifyTrackId) =>
      _box.get('spMatch:$spotifyTrackId') as String?;

  void rememberMatch(String spotifyTrackId, String videoId) =>
      _box.put('spMatch:$spotifyTrackId', videoId);

  /// Пропуск тишины в треках (Android).
  bool get skipSilence => _box.get('skipSilence', defaultValue: false) as bool;

  set skipSilence(bool value) => _box.put('skipSilence', value);

  int get crossfadeSeconds => _box.get('crossfadeSeconds', defaultValue: 0) as int;

  set crossfadeSeconds(int value) => _box.put('crossfadeSeconds', value);

  bool get shuffleEnabled =>
      _box.get('shuffleEnabled', defaultValue: false) as bool;

  set shuffleEnabled(bool value) => _box.put('shuffleEnabled', value);

  int get repeatIndex => _box.get('repeatIndex', defaultValue: 0) as int;

  set repeatIndex(int value) => _box.put('repeatIndex', value);

  String? get lastTrackId => _box.get('lastTrackId') as String?;

  set lastTrackId(String? value) => _box.put('lastTrackId', value);

  int get lastPositionMs =>
      (_box.get('lastPositionMs') as num?)?.toInt() ?? 0;

  set lastPositionMs(int value) => _box.put('lastPositionMs', value);

  double get playbackSpeed =>
      (_box.get('playbackSpeed') as num?)?.toDouble() ?? 1.0;

  set playbackSpeed(double value) => _box.put('playbackSpeed', value);

  int lyricsOffsetMs(String trackId) =>
      (_box.get('lyricsOffset:$trackId') as num?)?.toInt() ?? 0;

  void setLyricsOffsetMs(String trackId, int value) =>
      _box.put('lyricsOffset:$trackId', value);

  List<String> get searchQueries =>
      (_box.get('searchQueries') as List?)?.cast<String>().toList() ?? const [];

  void rememberQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final list = [...searchQueries]..removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    list.insert(0, trimmed);
    _box.put('searchQueries', list.take(12).toList());
  }

  void clearSearchQueries() => _box.delete('searchQueries');

  List<String> get recentIds =>
      (_box.get('recentIds') as List?)?.cast<String>().toList() ?? const [];

  Map<String, int> get playCounts {
    final raw = _box.get('playCounts');
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      };
    }
    return const {};
  }

  void recordPlay(String trackId) {
    if (trackId.isEmpty) return;
    final recent = [...recentIds]..remove(trackId);
    recent.insert(0, trackId);
    _box.put('recentIds', recent.take(100).toList());

    final counts = {...playCounts};
    counts[trackId] = (counts[trackId] ?? 0) + 1;
    _box.put('playCounts', counts);
  }

  void clearHistory() {
    _box.delete('recentIds');
    _box.delete('playCounts');
  }
}
