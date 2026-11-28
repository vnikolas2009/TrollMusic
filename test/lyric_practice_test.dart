import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/lyric_practice.dart';

void main() {
  test('результат зависит только от seed', () {
    const text = 'Hello darkness my old friend';
    expect(maskLyricLine(text, seed: 5), maskLyricLine(text, seed: 5));
  });

  test('скрывается минимум одно слово, длина и пробелы сохраняются', () {
    const text = 'Hello darkness my old friend';
    final masked = maskLyricLine(text, seed: 1);
    expect(masked == text, isFalse);
    expect(masked.contains('_'), isTrue);
    expect(masked.split(' ').length, text.split(' ').length);
  });

  test('короткие слова остаются, если есть длинные', () {
    final masked = maskLyricLine('I am so happy today', seed: 3, ratio: 1);
    expect(masked.startsWith('I am so '), isTrue);
    expect(masked.contains('happy'), isFalse);
  });

  test('одно слово скрывается целиком, пустая строка не меняется', () {
    expect(maskLyricLine('Привет', seed: 1), '______');
    expect(maskLyricLine('  ', seed: 1), '  ');
    expect(maskLyricLine('', seed: 1), '');
  });

  test('знаки препинания остаются на месте', () {
    final masked = maskLyricLine('Hello, world!', seed: 2, ratio: 1);
    expect(masked, '_____, _____!');
  });

  test('длинные слова маскируются не длиннее 10 знаков', () {
    expect(maskLyricLine('Internationalization', seed: 1), '__________');
  });

  test('practiceSegments: тот же текст, скрытые слова отдельными фрагментами', () {
    const text = 'Hello, world! Again';
    final parts = practiceSegments(text, seed: 2, ratio: 1);
    expect(parts.map((e) => e.text).join(), text);
    expect(parts.where((e) => e.hidden).map((e) => e.text), ['Hello', 'world', 'Again']);
    expect(parts.where((e) => !e.hidden).map((e) => e.text).join(), ', ! ');
  });

  test('practiceSegments: пустая строка и строка без слов', () {
    expect(practiceSegments('', seed: 1), isEmpty);
    final blank = practiceSegments('  ', seed: 1);
    expect(blank.single.hidden, isFalse);
  });
}
