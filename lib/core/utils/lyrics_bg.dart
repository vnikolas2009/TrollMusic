/// Прозрачность чёрного слоя поверх фона-картинки экрана текстов.
///
/// [dim] — общая сила затемнения (0.2–0.9). В режиме градиента верх
/// остаётся светлее, а низ темнее, чтобы текст читался по всей высоте.
({double top, double bottom}) lyricsBgScrim(double dim, {required bool gradient}) {
  final d = dim.clamp(0.2, 0.9).toDouble();
  if (!gradient) return (top: d, bottom: d);
  return (
    top: d * 0.6,
    bottom: (d + 0.4).clamp(0.0, 0.95).toDouble(),
  );
}

/// Допустимые расширения файла для фона.
const lyricsBgExtensions = <String>['png', 'jpg', 'jpeg', 'webp', 'gif'];
