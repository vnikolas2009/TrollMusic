class LyricWord {
  const LyricWord({
    required this.text,
    required this.start,
    this.end,
  });

  /// Текст слова.
  final String text;

  /// Момент начала произнесения слова.
  final Duration start;

  /// Момент окончания слова.
  /// Может отсутствовать, если его нельзя определить.
  final Duration? end;
}

class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
    this.words = const [],
  });

  /// Время начала строки.
  final Duration time;

  /// Полный текст строки без временных тегов.
  final String text;

  /// Временные метки отдельных слов.
  /// Для обычного LRC список будет пустым.
  final List<LyricWord> words;

  /// Есть ли синхронизация по словам.
  bool get hasWordTiming => words.isNotEmpty;

  /// Возвращает индекс слова, которое должно звучать в указанное время.
  int wordIndexAt(Duration position) {
    if (words.isEmpty || position < words.first.start) {
      return -1;
    }

    var found = -1;

    for (var i = 0; i < words.length; i++) {
      if (words[i].start <= position) {
        found = i;
      } else {
        break;
      }
    }

    return found;
  }

  /// Прогресс внутри текущего слова от 0.0 до 1.0.
  double wordProgressAt(Duration position) {
    final index = wordIndexAt(position);

    if (index < 0) return 0.0;

    final word = words[index];
    final nextStart = index + 1 < words.length
        ? words[index + 1].start
        : word.end;

    if (nextStart == null || nextStart <= word.start) {
      return 0.0;
    }

    final total = (nextStart - word.start).inMicroseconds;
    final elapsed = (position - word.start).inMicroseconds;

    if (total <= 0) return 0.0;

    return (elapsed / total).clamp(0.0, 1.0);
  }
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

  /// Индекс строки, соответствующей текущей позиции воспроизведения.
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