/// Доля воспроизведения `0..1`; для неизвестной длительности — `0`.
double fractionOf(Duration position, Duration total) {
  final totalMs = total.inMilliseconds;
  if (totalMs <= 0) return 0;
  return (position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
}

/// Доля `0..1` по горизонтальной координате касания внутри полосы шириной [width].
double fractionForDx(double dx, double width) {
  if (width <= 0) return 0;
  return (dx / width).clamp(0.0, 1.0).toDouble();
}

/// Позиция трека по доле `0..1`; значения вне диапазона обрезаются.
Duration durationForFraction(double fraction, Duration total) {
  final f = fraction.clamp(0.0, 1.0).toDouble();
  return Duration(milliseconds: (total.inMilliseconds * f).round());
}

/// Сдвиг позиции на [delta] с ограничением `0..total`.
/// Если длительность неизвестна (`total` равно нулю), верхней границы нет.
Duration shiftPosition(Duration position, Duration delta, Duration total) {
  final target = position + delta;
  if (target < Duration.zero) return Duration.zero;
  if (total > Duration.zero && target > total) return total;
  return target;
}
