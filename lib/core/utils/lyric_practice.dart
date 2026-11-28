import 'dart:math';

/// Режим тренировки: прячет часть слов строки, чтобы их вспомнить.
/// Скрытые слова заменяются чертами такой же длины (не длиннее 10).
/// Результат зависит только от [seed], поэтому строка не «мигает» при
/// перерисовке. В строке из двух и более слов скрывается минимум одно
/// слово, а короткие слова (до двух букв) остаются на виду, если есть
/// другие.
String maskLyricLine(String text, {required int seed, double ratio = 0.5}) {
  final parts = [for (final m in RegExp(r'\s+|\S+').allMatches(text)) m.group(0)!];
  final wordIdx = [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].trim().isNotEmpty) i,
  ];
  if (wordIdx.isEmpty) return text;

  final long = [
    for (final i in wordIdx)
      if (_letters(parts[i]) > 2) i,
  ];
  final pool = long.isEmpty ? wordIdx : long;

  final rng = Random(seed);
  final shuffled = [...pool]..shuffle(rng);
  final count = max(1, (pool.length * ratio.clamp(0.0, 1.0)).round());
  final hide = shuffled.take(count).toSet();

  final out = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    out.write(hide.contains(i) ? _mask(parts[i]) : parts[i]);
  }
  return out.toString();
}

int _letters(String word) =>
    word.runes.where((r) => String.fromCharCode(r).contains(RegExp(r'[\p{L}\p{N}]', unicode: true))).length;

String _mask(String word) {
  final core = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  return word.replaceAllMapped(core, (m) => '_' * m.group(0)!.length.clamp(2, 10));
}
