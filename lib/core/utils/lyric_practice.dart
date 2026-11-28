import 'dart:math';

/// Режим тренировки: прячет часть слов строки, чтобы их вспомнить.
/// Скрытые слова заменяются чертами такой же длины (не длиннее 10).
/// Результат зависит только от [seed], поэтому строка не «мигает» при
/// перерисовке. В строке из двух и более слов скрывается минимум одно
/// слово, а короткие слова (до двух букв) остаются на виду, если есть
/// другие.
String maskLyricLine(String text, {required int seed, double ratio = 0.5}) {
  final parts = _split(text);
  final hide = _pickHidden(parts, seed: seed, ratio: ratio);
  if (hide.isEmpty) return text;

  final out = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    out.write(hide.contains(i) ? _mask(parts[i]) : parts[i]);
  }
  return out.toString();
}

/// Фрагмент строки в режиме тренировки: [hidden] — буквы и цифры скрытого
/// слова (знаки препинания остаются видимыми).
class PracticeSegment {
  const PracticeSegment(this.text, {this.hidden = false});

  final String text;
  final bool hidden;
}

/// Те же слова, что скрывает [maskLyricLine], но строка разбита на
/// фрагменты: скрытые рисуются плашкой по ширине настоящего слова. Текст
/// при этом не меняется, поэтому строка не «прыгает» при открытии слов.
List<PracticeSegment> practiceSegments(
  String text, {
  required int seed,
  double ratio = 0.5,
}) {
  final parts = _split(text);
  final hide = _pickHidden(parts, seed: seed, ratio: ratio);
  if (hide.isEmpty) return text.isEmpty ? const [] : [PracticeSegment(text)];

  final out = <PracticeSegment>[];
  void add(String value, bool hidden) {
    if (value.isEmpty) return;
    if (out.isNotEmpty && out.last.hidden == hidden) {
      out[out.length - 1] = PracticeSegment(out.last.text + value, hidden: hidden);
    } else {
      out.add(PracticeSegment(value, hidden: hidden));
    }
  }

  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (!hide.contains(i)) {
      add(part, false);
      continue;
    }
    var last = 0;
    for (final m in _core.allMatches(part)) {
      add(part.substring(last, m.start), false);
      add(m.group(0)!, true);
      last = m.end;
    }
    add(part.substring(last), false);
  }
  return out;
}

final _core = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<String> _split(String text) =>
    [for (final m in RegExp(r'\s+|\S+').allMatches(text)) m.group(0)!];

/// Номера фрагментов-слов, которые нужно скрыть; пусто, если слов нет.
Set<int> _pickHidden(List<String> parts, {required int seed, required double ratio}) {
  final wordIdx = [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].trim().isNotEmpty) i,
  ];
  if (wordIdx.isEmpty) return const {};

  final long = [
    for (final i in wordIdx)
      if (_letters(parts[i]) > 2) i,
  ];
  final pool = long.isEmpty ? wordIdx : long;

  final rng = Random(seed);
  final shuffled = [...pool]..shuffle(rng);
  final count = max(1, (pool.length * ratio.clamp(0.0, 1.0)).round());
  return shuffled.take(count).toSet();
}

int _letters(String word) =>
    word.runes.where((r) => String.fromCharCode(r).contains(RegExp(r'[\p{L}\p{N}]', unicode: true))).length;

String _mask(String word) {
  return word.replaceAllMapped(_core, (m) => '_' * m.group(0)!.length.clamp(2, 10));
}
