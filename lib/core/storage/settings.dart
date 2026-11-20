import 'package:hive_flutter/hive_flutter.dart';

import '../config/app_config.dart';
import '../utils/proxy_address.dart';

class Settings {
  Settings(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  static Future<Settings> open() async {
    final box = await Hive.openBox<dynamic>(boxName);
    return Settings(box);
  }

  String get workerUrl =>
      (_box.get('workerUrl') as String?)?.trim().isNotEmpty == true
          ? (_box.get('workerUrl') as String).trim()
          : AppConfig.defaultWorkerUrl;

  set workerUrl(String value) => _box.put('workerUrl', value.trim());

  /// HTTP-прокси `host:port` для всех соединений приложения (пусто — напрямую).
  String get httpProxy => normalizeProxyAddress(_box.get('httpProxy') as String? ?? '');

  set httpProxy(String value) => _box.put('httpProxy', value.trim());

  /// Кэшировать проигрываемый аудиопоток на диск (мгновенный повтор, работа через прокси).
  bool get audioCache => _box.get('audioCache', defaultValue: false) as bool;

  set audioCache(bool value) => _box.put('audioCache', value);

  bool get useWorkerProxy => _box.get('useWorkerProxy', defaultValue: false) as bool;

  set useWorkerProxy(bool value) => _box.put('useWorkerProxy', value);

  List<String> get pipedInstances =>
      (_box.get('pipedInstances') as List?)?.cast<String>().toList() ??
      AppConfig.defaultPipedInstances;

  set pipedInstances(List<String> value) => _box.put('pipedInstances', value);

  List<String> get invidiousInstances =>
      (_box.get('invidiousInstances') as List?)?.cast<String>().toList() ??
      AppConfig.defaultInvidiousInstances;

  set invidiousInstances(List<String> value) =>
      _box.put('invidiousInstances', value);

  String get spotifyClientId => _box.get('spotifyClientId') as String? ?? '';

  set spotifyClientId(String value) => _box.put('spotifyClientId', value.trim());

  String get spotifyClientSecret =>
      _box.get('spotifyClientSecret') as String? ?? '';

  set spotifyClientSecret(String value) =>
      _box.put('spotifyClientSecret', value.trim());

  int get bitrate => _box.get('bitrate', defaultValue: AppConfig.defaultBitrate) as int;

  set bitrate(int value) => _box.put('bitrate', value);

  bool get preferOpus => _box.get('preferOpus', defaultValue: false) as bool;

  set preferOpus(bool value) => _box.put('preferOpus', value);

  bool get proxyAudioStreams =>
      _box.get('proxyAudioStreams', defaultValue: false) as bool;

  set proxyAudioStreams(bool value) => _box.put('proxyAudioStreams', value);

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
