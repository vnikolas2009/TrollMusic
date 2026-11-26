import 'package:hive_flutter/hive_flutter.dart';

class Settings {
  Settings(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  static Future<Settings> open() async {
    final box = await Hive.openBox<dynamic>(boxName);
    return Settings(box);
  }

  // ---------------------------------------------------------------- тексты

  /// Сам искать тексты для новых треков после импорта.
  bool get autoLyrics => _box.get('autoLyrics', defaultValue: true) as bool;

  set autoLyrics(bool value) => _box.put('autoLyrics', value);

  /// Порядок сортировки медиатеки (индекс `TrackSort`).
  int get sortIndex => (_box.get('sortIndex') as num?)?.toInt() ?? 0;

  set sortIndex(int value) => _box.put('sortIndex', value);

  // ----------------------------------------------------------------- тема

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

  /// Стиль показа текстов песен (`spotify`, `minimal`, `classic`).
  String get lyricsStyle =>
      _box.get('lyricsStyle', defaultValue: 'spotify') as String;

  set lyricsStyle(String value) => _box.put('lyricsStyle', value);

  /// Импортированные шрифты: JSON-записи `{id, name, file}`.
  List<String> get userFonts =>
      ((_box.get('userFonts') as List?) ?? const []).whereType<String>().toList();

  set userFonts(List<String> value) => _box.put('userFonts', value);

  /// Идентификатор выбранного импортированного шрифта; `null` — стандартный.
  String? get fontId => _box.get('fontId') as String?;

  set fontId(String? value) =>
      value == null ? _box.delete('fontId') : _box.put('fontId', value);

  // ----------------------------------------------------------- оформление

  /// Уровень толщины шрифта (0 — тонкий … 3 — жирный; 1 — обычный).
  int get weightLevel =>
      ((_box.get('weightLevel') as num?)?.toInt() ?? 1).clamp(0, 3);

  set weightLevel(int value) => _box.put('weightLevel', value);

  /// Масштаб текста интерфейса.
  double get textScale =>
      ((_box.get('textScale') as num?)?.toDouble() ?? 1.0)
          .clamp(0.85, 1.2)
          .toDouble();

  set textScale(double value) => _box.put('textScale', value);

  /// Масштаб текста песен.
  double get lyricsScale =>
      ((_box.get('lyricsScale') as num?)?.toDouble() ?? 1.0)
          .clamp(0.85, 1.4)
          .toDouble();

  set lyricsScale(double value) => _box.put('lyricsScale', value);

  /// Индекс `AnimationMode`.
  int get animationModeIndex =>
      (_box.get('animationMode') as num?)?.toInt() ?? 0;

  set animationModeIndex(int value) => _box.put('animationMode', value);

  /// Индекс `EffectsLevel` (по умолчанию «Обычные»).
  int get effectsIndex => (_box.get('effectsLevel') as num?)?.toInt() ?? 2;

  set effectsIndex(int value) => _box.put('effectsLevel', value);

  /// Индекс `CoverShape` (по умолчанию «Скруглённые»).
  int get coverShapeIndex => (_box.get('coverShape') as num?)?.toInt() ?? 1;

  set coverShapeIndex(int value) => _box.put('coverShape', value);

  /// Показывать текущую строку текста под обложкой в плеере.
  bool get showLyricPreview =>
      _box.get('showLyricPreview', defaultValue: true) as bool;

  set showLyricPreview(bool value) => _box.put('showLyricPreview', value);

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
