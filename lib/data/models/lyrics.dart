class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({
    this.lines = const [],
    this.plainText = '',
    this.synced = false,
    this.source = 'lrclib',
    this.title,
    this.artist,
  });

  final List<LyricLine> lines;
  final String plainText;
  final bool synced;
  final String source;
  final String? title;
  final String? artist;

  bool get isEmpty => lines.isEmpty && plainText.trim().isEmpty;

  int indexAt(Duration position) {
    if (lines.isEmpty) return -1;
    var found = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }
}
