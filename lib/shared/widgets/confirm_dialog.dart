import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Диалог подтверждения необратимого действия. Возвращает `true`, только
/// если пользователь нажал кнопку подтверждения.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Удалить',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
