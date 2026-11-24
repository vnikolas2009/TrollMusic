import '../../data/models/lyrics.dart';

abstract final class LrcParser {
  static final RegExp _timeTag = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );

  static final RegExp _wordTimeTag = RegExp(
    r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>',
  );

  static final RegExp _metaTag = RegExp(
    r'^\[(ar|ti|al|by|offset|length|re|ve):(.*)\]$',
    caseSensitive: false,
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  static Lyrics parse(String raw) {
    final trimmed = raw.replaceAll('\r\n', '\n').trim();

    if (trimmed.isEmpty) {
      return const Lyrics();
    }

    final lines = <LyricLine>[];
    final plain = StringBuffer();

    var hasTimestamps = false;

    for (final row in trimmed.split('\n')) {
      final line = row.trim();

      if (line.isEmpty) continue;

      if (_metaTag.hasMatch(line)) {
        continue;
      }

      final lineTimestamps = <Duration>[];
      var contentStart = 0;

      while (true) {
        final match = _timeTag.matchAsPrefix(line, contentStart);

        if (match == null) break;

        lineTimestamps.add(_parseTimestamp(match));
        contentStart = match.end;
      }

      if (lineTimestamps.isEmpty) {
        final text = _removeWordTags(line);

        if (text.isNotEmpty) {
          plain.writeln(text);
        }

        continue;
      }

      hasTimestamps = true;

      final content = line.substring(contentStart).trim();

      if (content.isEmpty) continue;

      final text = _removeWordTags(content);
      final words = _parseWordTimings(
        content,
        lineTimestamps.first,
      );

      for (final timestamp in lineTimestamps) {
        lines.add(
          LyricLine(
            time: timestamp,
            text: text,
            words: words,
          ),
        );
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));

    return Lyrics(
      lines: lines,
      plainText: hasTimestamps ? trimmed : plain.toString().trim(),
      synced: hasTimestamps && lines.isNotEmpty,
    );
  }

  static List<LyricWord> _parseWordTimings(
    String content,
    Duration lineTime,
  ) {
    final matches = _wordTimeTag.allMatches(content).toList();

    if (matches.isEmpty) {
      return const [];
    }

    final words = <LyricWord>[];

    final prefix = content.substring(0, matches.first.start).trim();

    if (prefix.isNotEmpty) {
      for (final word in _splitWords(prefix)) {
        words.add(
          LyricWord(
            text: word,
            start: lineTime,
          ),
        );
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];

      final segmentStart = match.end;
      final segmentEnd = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;

      final timestamp = _parseWordTimestamp(match);

      final segment = content
          .substring(segmentStart, segmentEnd)
          .trim();

      if (segment.isEmpty) continue;

      for (final word in _splitWords(segment)) {
        words.add(
          LyricWord(
            text: word,
            start: timestamp,
          ),
        );
      }
    }

    words.sort((a, b) => a.start.compareTo(b.start));

    return List.generate(words.length, (index) {
      final word = words[index];

      Duration? end;

      if (index + 1 < words.length) {
        final nextStart = words[index + 1].start;

        if (nextStart > word.start) {
          end = nextStart;
        }
      }

      return LyricWord(
        text: word.text,
        start: word.start,
        end: end,
      );
    });
  }

  static List<String> _splitWords(String text) {
    return text
        .trim()
        .split(_whitespace)
        .where((word) => word.isNotEmpty)
        .toList();
  }

  static String _removeWordTags(String text) {
    return text
        .replaceAll(_wordTimeTag, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  // Исправлено: Match вместо RegExpMatch.
  static Duration _parseTimestamp(Match match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = _parseFraction(match.group(3));

    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: fraction,
    );
  }

  // Исправлено: Match вместо RegExpMatch.
  static Duration _parseWordTimestamp(Match match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = _parseFraction(match.group(3));

    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: fraction,
    );
  }

  static int _parseFraction(String? raw) {
    if (raw == null || raw.isEmpty) return 0;

    return int.parse(
      raw.padRight(3, '0').substring(0, 3),
    );
  }

  static String toLrc(
    Lyrics lyrics, {
    String? title,
    String? artist,
  }) {
    final buffer = StringBuffer();

    if (title != null) {
      buffer.writeln('[ti:$title]');
    }

    if (artist != null) {
      buffer.writeln('[ar:$artist]');
    }

    for (final line in lyrics.lines) {
      buffer.writeln('${_stamp(line.time)}${line.text}');
    }

    return buffer.toString().trimRight();
  }

  static String _stamp(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');

    final seconds = (duration.inSeconds % 60)
        .toString()
        .padLeft(2, '0');

    final centiseconds = ((duration.inMilliseconds % 1000) ~/ 10)
        .toString()
        .padLeft(2, '0');

    return '[$minutes:$seconds.$centiseconds]';
  }
}
