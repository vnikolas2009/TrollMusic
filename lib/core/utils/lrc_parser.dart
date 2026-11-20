import '../../data/models/lyrics.dart';

abstract final class LrcParser {
  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _metaTag = RegExp(r'^\[(ar|ti|al|by|offset|length|re|ve):(.*)\]$');

  static Lyrics parse(String raw) {
    final trimmed = raw.replaceAll('\r\n', '\n').trim();
    if (trimmed.isEmpty) return const Lyrics();

    final lines = <LyricLine>[];
    var hasTimestamps = false;
    final plain = StringBuffer();

    for (final row in trimmed.split('\n')) {
      final line = row.trim();
      final meta = _metaTag.firstMatch(line);
      if (meta != null) continue;

      final matches = _timeTag.allMatches(line).toList();
      final text = line.replaceAll(_timeTag, '').trim();
      if (matches.isEmpty) {
        if (text.isNotEmpty) plain.writeln(text);
        continue;
      }

      hasTimestamps = true;
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final fractionRaw = m.group(3) ?? '0';
        final fraction = int.parse(fractionRaw.padRight(3, '0').substring(0, 3));
        lines.add(
          LyricLine(
            time: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: fraction,
            ),
            text: text,
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

  static String toLrc(Lyrics lyrics, {String? title, String? artist}) {
    final buffer = StringBuffer();
    if (title != null) buffer.writeln('[ti:$title]');
    if (artist != null) buffer.writeln('[ar:$artist]');
    for (final line in lyrics.lines) {
      buffer.writeln('${_stamp(line.time)}${line.text}');
    }
    return buffer.toString().trimRight();
  }

  static String _stamp(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final centis = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$centis]';
  }
}
