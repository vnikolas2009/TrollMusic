/// Отрезок трека для повтора. Границы — время в аудио.
class LoopRange {
  const LoopRange(this.start, this.end);

  final Duration start;
  final Duration end;

  /// Запас на задержку позиции: перемотка в начало срабатывает чуть раньше
  /// конца, чтобы не проигрывать лишнее.
  static const tolerance = Duration(milliseconds: 80);

  /// Позиция дошла до конца отрезка.
  bool reached(Duration position) => position + tolerance >= end;

  /// Позиция лежит внутри отрезка (с запасом на границе).
  bool contains(Duration position) =>
      position >= start - tolerance && position < end;

  @override
  bool operator ==(Object other) =>
      other is LoopRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Отрезок для повтора строки текста.
///
/// Время строк — время текста; в аудио оно сдвинуто на [offsetMs] (так же
/// считается подсветка: позиция + сдвиг). Конец — начало следующей строки,
/// для последней — 5 секунд; ограничивается длительностью трека.
/// Слишком короткий отрезок (< 0,5 с) не повторяется.
LoopRange? loopRangeForLine({
  required Duration lineTime,
  Duration? nextLineTime,
  int offsetMs = 0,
  Duration? trackDuration,
}) {
  final shift = Duration(milliseconds: offsetMs);
  var start = lineTime - shift;
  if (start < Duration.zero) start = Duration.zero;

  var end = (nextLineTime ?? lineTime + const Duration(seconds: 5)) - shift;
  if (trackDuration != null && end > trackDuration) end = trackDuration;

  if (end - start < const Duration(milliseconds: 500)) return null;
  return LoopRange(start, end);
}
