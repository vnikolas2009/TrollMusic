import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/lrc_parser.dart';
import 'package:trollmusic/core/utils/translation.dart';

void main() {
  test('исходные строки для текста с таймкодами и для обычного', () {
    final synced = LrcParser.parse('[00:01.00]one\n[00:02.00]two');
    expect(translationSourceLines(synced, ''), ['one', 'two']);

    const raw = 'a\nb\n\nc';
    final plain = LrcParser.parse(raw);
    expect(translationSourceLines(plain, raw), ['a', 'b', '', 'c']);
  });

  test('enhanced LRC: строки без меток слов, исходный разбор не затронут', () {
    const raw = '[00:01.00]<00:01.00>Hello <00:01.50>world';
    final lyrics = LrcParser.parse(raw);
    expect(translationSourceLines(lyrics, raw), ['Hello world']);
    expect(lyrics.lines.single.hasWordTiming, isTrue);
  });

  test('хэш стабилен и зависит от текста', () {
    expect(linesHash(['a', 'b']), linesHash(['a', 'b']));
    expect(linesHash(['a', 'b']) == linesHash(['a', 'c']), isFalse);
    expect(linesHash(['ab']) == linesHash(['a', 'b']), isFalse);
  });

  test('пакеты пропускают пустые строки и не превышают размер', () {
    final lines = ['aaaa', '', 'bbbb', 'cccc', ''];
    expect(chunkIndices(lines, maxChars: 100), [
      [0, 2, 3],
    ]);
    expect(chunkIndices(lines, maxChars: 10), [
      [0, 2],
      [3],
    ]);
    expect(chunkIndices(['', ' '], maxChars: 10), isEmpty);
  });

  test('разбор ответа сервиса', () {
    final parsed = parseTranslateResponse([
      [
        ['Привет\n', 'Hello\n', null, null, 10],
        ['Мир', 'World', null, null, 10],
      ],
      null,
      'en',
    ]);
    expect(parsed?.text, 'Привет\nМир');
    expect(parsed?.sourceLang, 'en');
    expect(parseTranslateResponse('мусор'), isNull);
    expect(parseTranslateResponse([[]]), isNull);
  });

  test('раскладка по строкам', () {
    expect(splitTranslated('а\nб\n', 2), ['а', 'б']);
    expect(splitTranslated('а\nб\nв', 2), isNull);
    expect(splitTranslated('а', 2), isNull);
  });

  test('сравнение языков', () {
    expect(sameLanguage('zh', 'zh-CN'), isTrue);
    expect(sameLanguage('en', 'ru'), isFalse);
    expect(sameLanguage(null, 'ru'), isFalse);
  });

  test('название языка', () {
    expect(translationLanguageName('ru'), 'Русский');
    expect(translationLanguageName('xx'), 'xx');
  });
}
