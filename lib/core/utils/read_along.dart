/// Слово строки: границы в исходном тексте и его позиция.
class ReadWord {
  const ReadWord(this.text, this.start, this.end);

  final String text;

  /// Индексы в исходной строке: `[start, end)`.
  final int start;
  final int end;

  int get length => end - start;
}

/// Делит строку на слова по пробелам. Пустые куски (двойные пробелы) пропускаются.
List<ReadWord> splitWords(String text) {
  final words = <ReadWord>[];
  var start = -1;
  for (var i = 0; i <= text.length; i++) {
    final isSpace = i == text.length || text.codeUnitAt(i) == 0x20;
    if (!isSpace && start < 0) start = i;
    if (isSpace && start >= 0) {
      words.add(ReadWord(text.substring(start, i), start, i));
      start = -1;
    }
  }
  return words;
}

/// Сколько «весит» слово по времени: длинные читаются дольше
/// (формула из Read Along: `0.2 + длина · 0.035`).
double wordDwell(int length) => 0.2 + length * 0.035;

/// Индекс читаемого слова при доле строки [progress] (`0..1`).
///
/// Время строки делится между словами пропорционально [wordDwell].
/// Пустой список слов даёт `-1`; значения вне `0..1` обрезаются.
int wordIndexForProgress(List<ReadWord> words, double progress) {
  if (words.isEmpty) return -1;

  final weights = [for (final word in words) wordDwell(word.length)];
  final total = weights.fold<double>(0, (sum, w) => sum + w);
  final target = progress.clamp(0.0, 1.0).toDouble() * total;

  var acc = 0.0;
  for (var i = 0; i < weights.length; i++) {
    acc += weights[i];
    if (target < acc) return i;
  }
  return words.length - 1;
}
