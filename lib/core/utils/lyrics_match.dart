/// Чистая логика подбора текстов: нормализация названий, варианты запросов
/// и выбор лучшего кандидата. Без сети и UI, покрыта тестами.

/// Запрос на поиск текста.
class LyricsQuery {
  const LyricsQuery({
    required this.title,
    required this.artist,
    this.album = '',
    this.durationSec = 0,
  });

  final String title;
  final String artist;
  final String album;
  final int durationSec;

  @override
  String toString() => '$artist — $title';
}

/// Найденный вариант текста у одного из источников.
class LyricsCandidate {
  const LyricsCandidate({
    required this.title,
    required this.artist,
    required this.source,
    this.album = '',
    this.durationSec = 0,
    this.synced,
    this.plain,
  });

  final String title;
  final String artist;
  final String album;
  final int durationSec;
  final String source;

  /// Текст в формате LRC (может быть enhanced).
  final String? synced;

  /// Обычный текст без таймкодов.
  final String? plain;

  bool get hasSynced => synced != null && synced!.trim().isNotEmpty;
  bool get hasPlain => plain != null && plain!.trim().isNotEmpty;
  bool get hasAny => hasSynced || hasPlain;
}

final RegExp _brackets = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
final RegExp _trackNumber = RegExp(r'^\s*(\d{1,3}\s*[.\-_)]\s*|0\d\s+)(?=\D)');
final RegExp _tailJunk = RegExp(
  r'\s+[-–—]\s*(remaster(ed)?(\s+\d{4})?|\d{4}\s+remaster(ed)?|live.*|radio edit|single version|album version|'
  r'mono|stereo|official.*|lyric video|audio|explicit|deluxe.*|bonus track|remix.*)\s*$',
  caseSensitive: false,
);
final RegExp _featPart = RegExp(
  r'\s+(feat\.?|ft\.?|featuring|при уч\.?|совместно с)\s+.*$',
  caseSensitive: false,
);
final RegExp _spaces = RegExp(r'\s+');
final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Название для поиска: без номера трека, скобок, feat. и хвостов вроде
/// «- Remastered 2011».
String cleanTitle(String title) {
  var t = title.replaceAll('_', ' ');
  t = t.replaceFirst(_trackNumber, '');
  t = t.replaceAll(_brackets, ' ');
  for (var i = 0; i < 3; i++) {
    final next = t.replaceFirst(_tailJunk, '');
    if (next == t) break;
    t = next;
  }
  t = t.replaceFirst(_featPart, '');
  return t.replaceAll(_spaces, ' ').trim();
}

/// Исполнитель для поиска: без скобок и feat.
String cleanArtist(String artist) {
  var a = artist.replaceAll('_', ' ').replaceAll(_brackets, ' ');
  a = a.replaceFirst(_featPart, '');
  return a.replaceAll(_spaces, ' ').trim();
}

/// Главный (первый) исполнитель из списка «A, B & C».
String primaryArtist(String artist) {
  final cleaned = cleanArtist(artist);
  final first = cleaned.split(RegExp(r'\s*(,|&|;|/| x | и | feat\.?| ft\.?)\s*', caseSensitive: false)).first;
  return first.trim();
}

/// Ключ для сравнения: нижний регистр, только буквы и цифры.
String normalizeKey(String value) =>
    value.toLowerCase().replaceAll('ё', 'е').replaceAll(_nonWord, ' ').trim();

/// Если в тегах нет исполнителя, а название выглядит как «Артист - Название»,
/// разделяет их. Иначе возвращает исходные значения.
({String title, String artist}) splitArtistFromTitle(String title, String artist) {
  final unknown = artist.trim().isEmpty ||
      artist.trim().toLowerCase() == 'неизвестный исполнитель' ||
      artist.trim().toLowerCase() == 'unknown artist';
  if (!unknown) return (title: title, artist: artist);

  final cleaned = title.replaceAll('_', ' ').replaceFirst(_trackNumber, '');
  final m = RegExp(r'^(.{1,80}?)\s+[-–—]\s+(.+)$').firstMatch(cleaned);
  if (m == null) return (title: cleaned.trim(), artist: artist);
  return (title: m.group(2)!.trim(), artist: m.group(1)!.trim());
}

/// Варианты запросов от самого точного к самому широкому. Без дублей.
List<LyricsQuery> buildQueries({
  required String title,
  required String artist,
  String album = '',
  int durationSec = 0,
}) {
  final split = splitArtistFromTitle(title, artist);
  final t = split.title;
  final a = split.artist;
  final knownArtist = normalizeKey(a).isNotEmpty &&
      normalizeKey(a) != normalizeKey(unknownArtistLabel);

  final cleanT = cleanTitle(t);
  final fullArtist = knownArtist ? cleanArtist(a) : '';
  final mainArtist = knownArtist ? primaryArtist(a) : '';

  final seen = <String>{};
  final out = <LyricsQuery>[];
  void add(String tt, String aa, {bool withAlbum = false, bool withDuration = false}) {
    if (tt.trim().isEmpty) return;
    final query = LyricsQuery(
      title: tt.trim(),
      artist: aa.trim(),
      album: withAlbum ? album : '',
      durationSec: withDuration ? durationSec : 0,
    );
    final key = '${normalizeKey(query.title)}|${normalizeKey(query.artist)}|'
        '${normalizeKey(query.album)}|${query.durationSec}';
    if (seen.add(key)) out.add(query);
  }

  add(cleanT, fullArtist, withAlbum: true, withDuration: true);
  add(cleanT, mainArtist, withDuration: true);
  if (cleanT != t.trim()) add(t, fullArtist);
  add(cleanT, '');
  return out;
}

/// Подпись неизвестного исполнителя (совпадает с `unknownArtist` в модели).
const unknownArtistLabel = 'Неизвестный исполнитель';

/// Насколько название кандидата похоже на искомое: 0..1.
double titleSimilarity(String wanted, String got) {
  final a = normalizeKey(cleanTitle(wanted));
  final b = normalizeKey(cleanTitle(got));
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final ta = a.split(' ').toSet();
  final tb = b.split(' ').toSet();
  final common = ta.intersection(tb).length;
  if (common == 0) return 0;
  final containment = common / (ta.length < tb.length ? ta.length : tb.length);
  final jaccard = common / ta.union(tb).length;
  return (containment * 0.6 + jaccard * 0.4).clamp(0.0, 1.0);
}

/// Совпадение исполнителей: 1 — один из исполнителей искомого есть у кандидата.
double artistSimilarity(String wanted, String got) {
  final w = normalizeKey(wanted);
  final g = normalizeKey(got);
  if (w.isEmpty || g.isEmpty) return 0.5;
  if (w == g) return 1;
  final wantedNames = wanted
      .split(RegExp(r'\s*(,|&|;|/| x | feat\.?| ft\.?)\s*', caseSensitive: false))
      .map(normalizeKey)
      .where((n) => n.isNotEmpty);
  for (final name in wantedNames) {
    if (g.contains(name) || name.contains(g)) return 1;
  }
  final ta = w.split(' ').toSet();
  final tb = g.split(' ').toSet();
  final common = ta.intersection(tb).length;
  return common == 0 ? 0 : common / (ta.length > tb.length ? ta.length : tb.length);
}

/// Оценка кандидата. `null` — не подходит. Чем больше, тем лучше.
double? scoreCandidate(LyricsQuery query, LyricsCandidate c) {
  if (!c.hasAny) return null;

  final title = titleSimilarity(query.title, c.title);
  if (title < 0.6) return null;

  final knownArtist = normalizeKey(query.artist).isNotEmpty;
  final artist = knownArtist ? artistSimilarity(query.artist, c.artist) : 0.5;
  if (knownArtist && artist < 0.25) return null;

  var score = title * 3 + artist * 2;

  if (query.durationSec > 0 && c.durationSec > 0) {
    final diff = (query.durationSec - c.durationSec).abs();
    if (diff > 15) return null;
    if (diff <= 2) {
      score += 1.5;
    } else if (diff <= 5) {
      score += 0.8;
    } else {
      score -= diff / 15;
    }
  }

  if (c.hasSynced) score += 0.7;
  if (c.synced != null && RegExp(r'<\d{1,3}:\d{2}').hasMatch(c.synced!)) score += 0.3;
  return score;
}

/// Лучший подходящий кандидат или `null`.
LyricsCandidate? pickBest(LyricsQuery query, Iterable<LyricsCandidate> candidates) {
  LyricsCandidate? best;
  var bestScore = double.negativeInfinity;
  for (final c in candidates) {
    final s = scoreCandidate(query, c);
    if (s == null) continue;
    if (s > bestScore) {
      best = c;
      bestScore = s;
    }
  }
  return best;
}

/// Совпадает ли файл с текстом [lyricsFileName] (без расширения) с треком.
/// Нужен для пакетного импорта .lrc: «Артист - Название.lrc», «Название.lrc».
bool lyricsFileMatchesTrack({
  required String lyricsFileName,
  required String title,
  required String artist,
  String audioFileName = '',
}) {
  final file = normalizeKey(lyricsFileName);
  if (file.isEmpty) return false;
  if (audioFileName.isNotEmpty && normalizeKey(audioFileName) == file) return true;

  final t = normalizeKey(cleanTitle(title));
  if (t.isEmpty) return false;
  final a = normalizeKey(primaryArtist(artist));

  if (file == t) return true;
  if (a.isNotEmpty && (file == '$a $t' || file == '$t $a')) return true;

  final split = splitArtistFromTitle(lyricsFileName, '');
  final fileTitle = normalizeKey(cleanTitle(split.title));
  final fileArtist = normalizeKey(primaryArtist(split.artist));
  if (fileTitle.isEmpty || fileTitle != t) return false;
  return fileArtist.isEmpty || a.isEmpty || fileArtist == a || fileArtist.contains(a) || a.contains(fileArtist);
}
