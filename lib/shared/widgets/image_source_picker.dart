import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/lyrics_bg.dart';

/// Откуда брать картинку или GIF.
enum ImageSourceKind { library, files }

/// Спрашивает источник (медиатека телефона или файлы) и открывает
/// системный выбор. Возвращает путь к файлу или `null`, если пользователь
/// отказался.
Future<String?> pickImagePath(
  BuildContext context, {
  String title = 'Выбрать изображение',
}) async {
  final kind = await showModalBottomSheet<ImageSourceKind>(
    context: context,
    backgroundColor: AppColors.surfaceAlt,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Из медиатеки'),
            subtitle: const Text('Фото и GIF из галереи'),
            onTap: () => Navigator.pop(sheet, ImageSourceKind.library),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Из файлов'),
            subtitle: const Text('PNG, JPG, WebP или GIF'),
            onTap: () => Navigator.pop(sheet, ImageSourceKind.files),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (kind == null) return null;

  final picked = switch (kind) {
    ImageSourceKind.library => await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: title,
      ),
    ImageSourceKind.files => await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: lyricsBgExtensions,
        dialogTitle: title,
      ),
  };
  return picked?.path;
}
