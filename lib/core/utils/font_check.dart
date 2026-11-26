import 'dart:convert';
import 'dart:typed_data';

/// Результат проверки файла шрифта.
class FontCheck {
  const FontCheck.ok(String this.family) : error = null;
  const FontCheck.fail(String this.error) : family = null;

  /// Имя семейства из таблицы `name`; `null`, если проверка не пройдена.
  final String? family;

  /// Причина отказа для пользователя; `null`, если файл годится.
  final String? error;

  bool get ok => error == null;
}

/// Максимальный размер импортируемого шрифта.
const int maxFontBytes = 25 * 1024 * 1024;

/// Проверяет, что [bytes] — целый TrueType/OpenType-шрифт: заголовок, таблица
/// таблиц, обязательные таблицы и сигнатура `head`. Это отсекает чужие и
/// повреждённые файлы до того, как их увидит движок. Читает только внутри
/// границ файла и никогда не бросает исключений.
FontCheck checkFontBytes(Uint8List bytes) {
  if (bytes.length < 12) return const FontCheck.fail('Файл пустой или слишком маленький');
  if (bytes.length > maxFontBytes) {
    return const FontCheck.fail('Файл больше 25 МБ');
  }

  final data = ByteData.sublistView(bytes);
  final tag = data.getUint32(0);

  const truetype = 0x00010000;
  const trueTag = 0x74727565; // 'true'
  const otto = 0x4F54544F; // 'OTTO'
  const ttcf = 0x74746366; // 'ttcf'

  if (tag == ttcf) {
    return const FontCheck.fail('Коллекции шрифтов (.ttc) не поддерживаются');
  }
  if (tag != truetype && tag != trueTag && tag != otto) {
    return const FontCheck.fail('Это не шрифт TTF или OTF');
  }

  final numTables = data.getUint16(4);
  if (numTables == 0 || numTables > 128 || 12 + numTables * 16 > bytes.length) {
    return const FontCheck.fail('Файл шрифта повреждён');
  }

  final tables = <String, ({int offset, int length})>{};
  for (var i = 0; i < numTables; i++) {
    final at = 12 + i * 16;
    final name = String.fromCharCodes(bytes.sublist(at, at + 4));
    final offset = data.getUint32(at + 8);
    final length = data.getUint32(at + 12);
    if (offset > bytes.length || length > bytes.length - offset) {
      return const FontCheck.fail('Файл шрифта повреждён или обрезан');
    }
    tables[name] = (offset: offset, length: length);
  }

  for (final required in const ['cmap', 'head', 'maxp', 'name']) {
    if (!tables.containsKey(required)) {
      return FontCheck.fail('В шрифте нет обязательной таблицы «$required»');
    }
  }
  final hasOutlines = (tables.containsKey('glyf') && tables.containsKey('loca')) ||
      tables.containsKey('CFF ') ||
      tables.containsKey('CFF2');
  if (!hasOutlines) {
    return const FontCheck.fail('В шрифте нет контуров символов');
  }

  final head = tables['head']!;
  if (head.length < 54 || data.getUint32(head.offset + 12) != 0x5F0F3CF5) {
    return const FontCheck.fail('Файл шрифта повреждён (заголовок head)');
  }

  final family = _familyName(bytes, tables['name']!);
  if (family == null) {
    return const FontCheck.fail('Не удалось прочитать название шрифта');
  }
  return FontCheck.ok(family);
}

/// Имя семейства: предпочтительное (nameID 16), иначе обычное (nameID 1).
/// Windows-записи (UTF-16BE) важнее Mac-записей.
String? _familyName(Uint8List bytes, ({int offset, int length}) table) {
  final data = ByteData.sublistView(bytes);
  final base = table.offset;
  if (table.length < 6) return null;

  final count = data.getUint16(base + 2);
  final storage = base + data.getUint16(base + 4);
  if (6 + count * 12 > table.length) return null;

  String? best;
  var bestScore = -1;

  for (var i = 0; i < count; i++) {
    final at = base + 6 + i * 12;
    final platform = data.getUint16(at);
    final language = data.getUint16(at + 4);
    final nameId = data.getUint16(at + 6);
    final length = data.getUint16(at + 8);
    final offset = data.getUint16(at + 10);
    if (nameId != 1 && nameId != 16) continue;

    final start = storage + offset;
    if (start < 0 || start + length > bytes.length) continue;
    final raw = bytes.sublist(start, start + length);

    String text;
    if (platform == 3 || platform == 0) {
      if (raw.length.isOdd) continue;
      final units = <int>[
        for (var j = 0; j < raw.length; j += 2) (raw[j] << 8) | raw[j + 1],
      ];
      text = String.fromCharCodes(units);
    } else if (platform == 1) {
      text = latin1.decode(raw, allowInvalid: true);
    } else {
      continue;
    }
    text = text.trim();
    if (text.isEmpty) continue;

    final score = (nameId == 16 ? 4 : 0) +
        ((platform == 3 || platform == 0) ? 2 : 0) +
        (language == 0x409 ? 1 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = text;
    }
  }
  return best;
}
