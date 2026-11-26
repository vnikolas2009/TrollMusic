import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/settings.dart';
import '../../core/utils/font_check.dart';

/// Импортированный пользователем шрифт. Файл лежит в папке приложения
/// (`fonts/<file>`), в настройках хранится только имя файла: так запись
/// переживает смену контейнера на iOS.
class UserFont {
  const UserFont({required this.id, required this.name, required this.file});

  final String id;
  final String name;
  final String file;

  /// Имя семейства, под которым шрифт зарегистрирован во Flutter.
  String get family => FontService.familyOf(id);

  Map<String, String> toJson() => {'id': id, 'name': name, 'file': file};

  static UserFont? tryParse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final id = map['id'];
      final name = map['name'];
      final file = map['file'];
      if (id is! String || name is! String || file is! String) return null;
      if (id.isEmpty || file.isEmpty || p.basename(file) != file) return null;
      return UserFont(id: id, name: name, file: file);
    } catch (_) {
      return null;
    }
  }
}

/// Шрифт, прошедший проверку, но ещё не добавленный в список.
class PendingFont {
  const PendingFont({
    required this.id,
    required this.name,
    required this.extension,
    required this.bytes,
  });

  final String id;
  final String name;
  final String extension;
  final Uint8List bytes;

  String get family => FontService.familyOf(id);
}

/// Ошибка импорта с готовым для пользователя текстом.
class FontImportException implements Exception {
  const FontImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Хранение и загрузка пользовательских шрифтов (TTF/OTF).
class FontService {
  FontService({required this.settings, required this.root});

  final Settings settings;

  /// Корневая папка приложения ([StorageService.root]).
  final Directory root;

  static String familyOf(String id) => 'user_$id';

  Directory get dir => Directory(p.join(root.path, 'fonts'));

  /// Сохранённые шрифты; битые записи пропускаются.
  List<UserFont> get fonts => [
        for (final raw in settings.userFonts)
          if (UserFont.tryParse(raw) case final font?) font,
      ];

  void _save(List<UserFont> list) {
    settings.userFonts = [for (final f in list) jsonEncode(f.toJson())];
  }

  Future<void> _register(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  /// Регистрирует сохранённые шрифты до первого кадра. Файлы, которых нет
  /// или которые не проходят проверку, выбрасываются из списка; если
  /// выбранный шрифт не загрузился, возвращается стандартный.
  Future<void> loadSaved() async {
    final kept = <UserFont>[];
    for (final font in fonts) {
      try {
        final bytes = await File(p.join(dir.path, font.file)).readAsBytes();
        if (!checkFontBytes(bytes).ok) continue;
        await _register(font.family, bytes);
        kept.add(font);
      } catch (_) {
        // файл удалён или повреждён — запись не нужна
      }
    }
    if (kept.length != fonts.length) _save(kept);
    final selected = settings.fontId;
    if (selected != null && !kept.any((f) => f.id == selected)) {
      settings.fontId = null;
    }
  }

  /// Читает и проверяет файл, регистрирует его для предпросмотра. Бросает
  /// [FontImportException] с понятным текстом.
  Future<PendingFont> prepare(String path) async {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext != 'ttf' && ext != 'otf') {
      throw const FontImportException('Нужен файл TTF или OTF');
    }

    final Uint8List bytes;
    try {
      final file = File(path);
      if (await file.length() > maxFontBytes) {
        throw const FontImportException('Файл больше 25 МБ');
      }
      bytes = await file.readAsBytes();
    } on FontImportException {
      rethrow;
    } catch (_) {
      throw const FontImportException('Не удалось прочитать файл');
    }

    final check = checkFontBytes(bytes);
    if (!check.ok) throw FontImportException(check.error!);

    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    try {
      await _register(familyOf(id), bytes);
    } catch (_) {
      throw const FontImportException('Шрифт не удалось загрузить');
    }
    return PendingFont(
      id: id,
      name: check.family!,
      extension: ext,
      bytes: bytes,
    );
  }

  /// Сохраняет подтверждённый шрифт в папку приложения и в список.
  Future<UserFont> add(PendingFont pending) async {
    await dir.create(recursive: true);
    final file = '${pending.id}.${pending.extension}';
    await File(p.join(dir.path, file)).writeAsBytes(pending.bytes, flush: true);

    final font = UserFont(id: pending.id, name: pending.name, file: file);
    _save([...fonts, font]);
    return font;
  }

  /// Удаляет шрифт и его файл. Если он был выбран — возвращает стандартный.
  Future<void> remove(String id) async {
    final list = fonts;
    for (final font in list.where((f) => f.id == id)) {
      try {
        await File(p.join(dir.path, font.file)).delete();
      } catch (_) {}
    }
    _save([for (final f in list) if (f.id != id) f]);
    if (settings.fontId == id) settings.fontId = null;
  }
}
