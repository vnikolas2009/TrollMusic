import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/font_check.dart';

/// Собирает минимальный sfnt-файл из таблиц (контрольные суммы не нужны).
Uint8List buildFont(
  Map<String, Uint8List> tables, {
  int sfnt = 0x00010000,
}) {
  final count = tables.length;
  var offset = 12 + count * 16;
  final header = BytesBuilder()
    ..add((ByteData(12)
          ..setUint32(0, sfnt)
          ..setUint16(4, count))
        .buffer
        .asUint8List());
  final body = BytesBuilder();
  for (final entry in tables.entries) {
    final record = ByteData(16)
      ..setUint32(8, offset)
      ..setUint32(12, entry.value.length);
    final bytes = record.buffer.asUint8List();
    bytes.setRange(0, 4, ascii.encode(entry.key.padRight(4)));
    header.add(bytes);
    body.add(entry.value);
    offset += entry.value.length;
  }
  return Uint8List.fromList([...header.toBytes(), ...body.toBytes()]);
}

Uint8List headTable({int magic = 0x5F0F3CF5}) {
  final d = ByteData(54)..setUint32(12, magic);
  return d.buffer.asUint8List();
}

Uint8List nameTable(String family, {int nameId = 1}) {
  final text = Uint8List.fromList([
    for (final u in family.codeUnits) ...[u >> 8, u & 0xFF],
  ]);
  final d = ByteData(6 + 12)
    ..setUint16(2, 1)
    ..setUint16(4, 18)
    ..setUint16(6, 3)
    ..setUint16(8, 1)
    ..setUint16(10, 0x409)
    ..setUint16(12, nameId)
    ..setUint16(14, text.length)
    ..setUint16(16, 0);
  return Uint8List.fromList([...d.buffer.asUint8List(), ...text]);
}

Map<String, Uint8List> goodTables({String family = 'Test Font'}) => {
      'cmap': Uint8List(4),
      'glyf': Uint8List(4),
      'head': headTable(),
      'loca': Uint8List(4),
      'maxp': Uint8List(6),
      'name': nameTable(family),
    };

void main() {
  group('checkFontBytes', () {
    test('принимает корректный TrueType и читает название', () {
      final check = checkFontBytes(buildFont(goodTables()));
      expect(check.ok, isTrue);
      expect(check.family, 'Test Font');
    });

    test('принимает OpenType с контурами CFF', () {
      final tables = goodTables()
        ..remove('glyf')
        ..remove('loca')
        ..['CFF '] = Uint8List(4);
      expect(checkFontBytes(buildFont(tables, sfnt: 0x4F54544F)).ok, isTrue);
    });

    test('предпочитает название семейства nameID 16', () {
      final tables = goodTables()..['name'] = nameTable('Pref Family', nameId: 16);
      expect(checkFontBytes(buildFont(tables)).family, 'Pref Family');
    });

    test('отклоняет пустой, маленький и чужой файл', () {
      expect(checkFontBytes(Uint8List(0)).ok, isFalse);
      expect(checkFontBytes(Uint8List(8)).ok, isFalse);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(64, 0)]);
      expect(checkFontBytes(png).ok, isFalse);
    });

    test('отклоняет коллекции .ttc', () {
      final ttc = Uint8List.fromList([0x74, 0x74, 0x63, 0x66, ...List.filled(64, 0)]);
      final check = checkFontBytes(ttc);
      expect(check.ok, isFalse);
      expect(check.error, contains('ttc'));
    });

    test('отклоняет обрезанный файл', () {
      final font = buildFont(goodTables());
      expect(checkFontBytes(font.sublist(0, font.length - 30)).ok, isFalse);
    });

    test('отклоняет шрифт без обязательной таблицы или контуров', () {
      expect(checkFontBytes(buildFont(goodTables()..remove('cmap'))).ok, isFalse);
      final noOutlines = goodTables()
        ..remove('glyf')
        ..remove('loca');
      expect(checkFontBytes(buildFont(noOutlines)).ok, isFalse);
    });

    test('отклоняет неверную сигнатуру head', () {
      final tables = goodTables()..['head'] = headTable(magic: 0xDEADBEEF);
      expect(checkFontBytes(buildFont(tables)).ok, isFalse);
    });

    test('не бросает исключений на мусоре', () {
      final junk = Uint8List.fromList(List.generate(500, (i) => (i * 37) & 0xFF));
      expect(() => checkFontBytes(junk), returnsNormally);
      expect(checkFontBytes(junk).ok, isFalse);
    });
  });
}
