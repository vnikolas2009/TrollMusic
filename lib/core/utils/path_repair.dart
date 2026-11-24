import 'dart:io';

import 'package:path/path.dart' as p;

/// Подбирает актуальный путь к файлу, если сохранённый устарел.
///
/// На iOS папка приложения содержит случайный идентификатор, который
/// меняется при переустановке или обновлении IPA: абсолютный путь в базе
/// указывает в никуда, хотя файл лежит в новой папке. Ищем файл с тем же
/// именем в `<root>/<родительская папка>/`.
///
/// Возвращает `null`, если путь не нужно менять (файл на месте или найти
/// замену не удалось).
String? repairedPath(
  String? stored,
  String root, {
  bool Function(String path)? exists,
}) {
  if (stored == null || stored.isEmpty) return null;
  final check = exists ?? (path) => File(path).existsSync();
  if (check(stored)) return null;

  final name = p.basename(stored);
  final folder = p.basename(p.dirname(stored));
  if (name.isEmpty || folder.isEmpty || folder == '.' || folder == p.separator) {
    return null;
  }
  final candidate = p.join(root, folder, name);
  return check(candidate) ? candidate : null;
}

/// Имя файла без символов, недопустимых в файловых системах (`sc:123`).
String safeFileName(String id) =>
    id.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
