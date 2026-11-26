import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/lrc_parser.dart';

void main() {
  group('LrcParser.plainLines', () {
    test('сохраняет границы куплетов и схлопывает лишние пустые строки', () {
      const raw = 'Первая\nВторая\n\n\n\nТретья\n';
      expect(
        LrcParser.plainLines(raw),
        ['Первая', 'Вторая', '', 'Третья'],
      );
    });

    test('убирает служебные теги и метки времени', () {
      const raw = '[ar:Артист]\n[ti:Название]\n[00:01.00]Строка\n'
          '[00:02.00]<00:02.00>Ещё <00:02.50>одна';
      expect(LrcParser.plainLines(raw), ['Строка', 'Ещё одна']);
    });

    test('пустой ввод даёт пустой список', () {
      expect(LrcParser.plainLines('  \n\n '), isEmpty);
    });
  });
}
