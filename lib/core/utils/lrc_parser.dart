import '../../data/models/lyrics.dart';

/// Разбор и запись LRC: обычного (`[мм:сс.хх]текст`) и enhanced с метками
/// слов (`[мм:сс.хх]<мм:сс.хх>слово <мм:сс.хх>слово`).
abstract final class LrcParser {
  static final RegExp _lineTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _wordTag =
      RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');
  static final RegExp _metaTag =
      RegExp(r'^\[([a-zA-Z#]+):(.*)\]$');
  static final RegExp _spaces = RegExp(r'\s+');

  static String _normalize(String raw) => raw
      .replaceAll('﻿', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();

  /// Есть ли в тексте хотя бы одна временная метка строки.
  static bool looksSynced(String raw) => _lineTag.hasMatch(raw);

  /// Есть ли пословные метки (enhanced LRC).
  static bool hasWordTiming(String raw) => _wordTag.hasMatch(raw);

  /// Теги `[ti:]`, `[ar:]`, `[al:]` из заголовка LRC.
  static ({String? title, String? artist, String? album}) readMeta(String raw) {
    String? title;
    String? artist;
    String? album;
    for (final row in _normalize(raw).split('\n')) {
      final m = _metaTag.firstMatch(row.trim());
      if (m == null) continue;
      final key = m.group(1)!.toLowerCase();
      final value = m.group(2)!.trim();
      if (value.isEmpty) continue;
      if (key == 'ti') title ??= value;
      if (key == 'ar') artist ??= value;
      if (key == 'al') album ??= value;
    }
    return (title: title, artist: artist, album: album);
  }

  static Lyrics parse(String raw) {
    final text = _normalize(raw);
    if (text.isEmpty) return const Lyrics();

    var offsetMs = 0;
    final lines = <LyricLine>[];
    final plain = StringBuffer();
    var synced = false;

    for (final row in text.split('\n')) {
      final line = row.trim();
      if (line.isEmpty) continue;

      final meta = _metaTag.firstMatch(line);
      if (meta != null && !_lineTag.hasMatch(line)) {
        if (meta.group(1)!.toLowerCase() == 'offset') {
          offsetMs = int.tryParse(meta.group(2)!.trim().replaceFirst('+', '')) ?? 0;
        }
        continue;
      }

      final stamps = <Duration>[];
      var pos = 0;
      while (true) {
        final m = _lineTag.matchAsPrefix(line, pos);
        if (m == null) break;
        stamps.add(_duration(m));
        pos = m.end;
      }

      final content = line.substring(pos).trim();

      // Строка без метки строки, но с метками слов: время берём у первого слова.
      if (stamps.isEmpty) {
        final first = _wordTag.firstMatch(content);
        if (first == null) {
          final clean = _stripWordTags(content);
          if (clean.isNotEmpty) plain.writeln(clean);
          continue;
        }
        stamps.add(_duration(first));
      }

      final clean = _stripWordTags(content);
      if (clean.isEmpty) continue;
      synced = true;

      for (final stamp in stamps) {
        final shift = Duration(milliseconds: offsetMs);
        final time = _shifted(stamp, shift);
        lines.add(LyricLine(
          time: time,
          text: clean,
          words: _words(content, stamp, shift),
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));

    return Lyrics(
      lines: lines,
      plainText: synced ? text : plain.toString().trim(),
      synced: synced && lines.isNotEmpty,
    );
  }

  /// Строки текста без таймкодов для показа: метки времени и служебные теги
  /// убраны, границы куплетов сохранены как пустые строки (подряд идущие
  /// пустые схлопываются, в начале и в конце их нет).
  static List<String> plainLines(String raw) {
    final out = <String>[];
    for (final row in _normalize(raw).split('\n')) {
      final line = row.trim();
      if (line.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        continue;
      }
      if (_metaTag.hasMatch(line) && !_lineTag.hasMatch(line)) continue;

      var pos = 0;
      while (true) {
        final m = _lineTag.matchAsPrefix(line, pos);
        if (m == null) break;
        pos = m.end;
      }
      final clean = _stripWordTags(line.substring(pos).trim());
      if (clean.isNotEmpty) out.add(clean);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }

  /// Положительный `[offset:]` — текст появляется раньше, как в большинстве плееров.
  static Duration _shifted(Duration value, Duration offset) {
    final result = value - offset;
    return result.isNegative ? Duration.zero : result;
  }

  static List<LyricWord> _words(String content, Duration lineTime, Duration shift) {
    final tags = _wordTag.allMatches(content).toList();
    if (tags.isEmpty) return const [];

    final out = <LyricWord>[];
    Duration? trailingEnd;

    final prefix = content.substring(0, tags.first.start).trim();
    for (final w in _split(prefix)) {
      out.add(LyricWord(text: w, start: _shifted(lineTime, shift)));
    }

    for (var i = 0; i < tags.length; i++) {
      final start = _shifted(_duration(tags[i]), shift);
      final segEnd = i + 1 < tags.length ? tags[i + 1].start : content.length;
      final segment = content.substring(tags[i].end, segEnd).trim();
      if (segment.isEmpty) {
        // Метка без слова после неё: конец предыдущего слова.
        if (i + 1 == tags.length) trailingEnd = start;
        continue;
      }
      for (final w in _split(segment)) {
        out.add(LyricWord(text: w, start: start));
      }
    }

    out.sort((a, b) => a.start.compareTo(b.start));

    return List.generate(out.length, (i) {
      final w = out[i];
      Duration? end;
      if (i + 1 < out.length) {
        if (out[i + 1].start > w.start) end = out[i + 1].start;
      } else if (trailingEnd != null && trailingEnd > w.start) {
        end = trailingEnd;
      }
      return LyricWord(text: w.text, start: w.start, end: end);
    });
  }

  static List<String> _split(String text) =>
      text.split(_spaces).where((w) => w.isNotEmpty).toList();

  static String _stripWordTags(String text) =>
      text.replaceAll(_wordTag, '').replaceAll(_spaces, ' ').trim();

  static Duration _duration(Match m) {
    final fraction = m.group(3);
    final ms = fraction == null || fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(
      minutes: int.parse(m.group(1)!),
      seconds: int.parse(m.group(2)!),
      milliseconds: ms,
    );
  }

  /// Собирает LRC из разобранного текста. Если у строк есть метки слов,
  /// получится enhanced LRC.
  static String toLrc(Lyrics lyrics, {String? title, String? artist}) {
    final b = StringBuffer();
    if (title != null && title.isNotEmpty) b.writeln('[ti:$title]');
    if (artist != null && artist.isNotEmpty) b.writeln('[ar:$artist]');

    for (final line in lyrics.lines) {
      b.write(_stamp(line.time, '[', ']'));
      if (line.hasWordTiming) {
        b.writeln(line.words
            .map((w) => '${_stamp(w.start, '<', '>')}${w.text}')
            .join(' '));
      } else {
        b.writeln(line.text);
      }
    }
    return b.toString().trimRight();
  }

  static String _stamp(Duration d, String open, String close) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$open$m:$s.$cs$close';
  }
}
