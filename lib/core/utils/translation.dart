import '../../data/models/lyrics.dart';
import 'lrc_parser.dart';

/// Языки перевода: код и название для интерфейса.
const translationLanguages = <({String code, String name})>[
  (code: 'ru', name: 'Русский'),
  (code: 'en', name: 'English'),
  (code: 'uk', name: 'Українська'),
  (code: 'es', name: 'Español'),
  (code: 'de', name: 'Deutsch'),
  (code: 'fr', name: 'Français'),
  (code: 'it', name: 'Italiano'),
  (code: 'pt', name: 'Português'),
  (code: 'tr', name: 'Türkçe'),
  (code: 'ja', name: '日本語'),
  (code: 'ko', name: '한국어'),
  (code: 'zh-CN', name: '中文'),
];

String translationLanguageName(String code) {
  for (final l in translationLanguages) {
    if (l.code == code) return l.name;
  }
  return code;
}

/// Строки текста в том порядке, в каком они показываются на экране:
/// для текстов с таймкодами — строки LRC, для обычных — строки текста с
/// пустыми разделителями куплетов. Перевод хранится по индексу этого списка,
/// поэтому исходный (в том числе enhanced) LRC не меняется.
List<String> translationSourceLines(Lyrics lyrics, String raw) {
  if (lyrics.synced) return [for (final l in lyrics.lines) l.text];
  return LrcParser.plainLines(raw);
}

/// Устойчивый хэш (FNV-1a) исходных строк: по нему кэш перевода
/// устаревает, когда текст песни меняется.
String linesHash(List<String> lines) {
  var hash = 0x811c9dc5;
  void feed(int unit) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }

  for (final line in lines) {
    for (final unit in line.codeUnits) {
      feed(unit);
    }
    feed(10);
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Индексы непустых строк, разбитые на пакеты не длиннее [maxChars] символов.
List<List<int>> chunkIndices(List<String> lines, {int maxChars = 3000}) {
  final chunks = <List<int>>[];
  var current = <int>[];
  var size = 0;
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].trim();
    if (text.isEmpty) continue;
    if (current.isNotEmpty && size + text.length + 1 > maxChars) {
      chunks.add(current);
      current = <int>[];
      size = 0;
    }
    current.add(i);
    size += text.length + 1;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Разбирает ответ `translate_a/single`: склеивает переведённые фрагменты и
/// определяет исходный язык.
({String text, String? sourceLang})? parseTranslateResponse(Object? json) {
  if (json is! List || json.isEmpty || json.first is! List) return null;
  final buffer = StringBuffer();
  for (final part in json.first as List) {
    if (part is List && part.isNotEmpty && part.first is String) {
      buffer.write(part.first as String);
    }
  }
  final text = buffer.toString();
  if (text.isEmpty) return null;
  final lang = json.length > 2 && json[2] is String ? json[2] as String : null;
  return (text: text, sourceLang: lang);
}

/// Раскладывает переведённый текст обратно по строкам. Возвращает `null`,
/// если число строк не совпало с числом исходных (тогда нужен перевод по
/// одной строке).
List<String>? splitTranslated(String translated, int expected) {
  final rows = translated
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((e) => e.trim())
      .toList();
  while (rows.isNotEmpty && rows.last.isEmpty) {
    rows.removeLast();
  }
  return rows.length == expected ? rows : null;
}

/// Совпадает ли исходный язык с языком перевода (`zh-CN` и `zh` считаются
/// одним языком).
bool sameLanguage(String? source, String target) {
  if (source == null) return false;
  String base(String c) => c.toLowerCase().split(RegExp('[-_]')).first;
  return base(source) == base(target);
}
