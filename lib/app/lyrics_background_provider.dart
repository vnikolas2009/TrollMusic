import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/lyrics_bg.dart';
import 'providers.dart';
import 'settings_provider.dart';

@immutable
class LyricsBackground {
  const LyricsBackground({this.path, this.dim = 0.55, this.gradient = true});

  /// Полный путь к картинке или `null`, если фон не выбран.
  final String? path;
  final double dim;
  final bool gradient;

  String? get fileName => path == null ? null : p.basename(path!);

  LyricsBackground copyWith({double? dim, bool? gradient}) => LyricsBackground(
        path: path,
        dim: dim ?? this.dim,
        gradient: gradient ?? this.gradient,
      );

  @override
  bool operator ==(Object other) =>
      other is LyricsBackground &&
      other.path == path &&
      other.dim == dim &&
      other.gradient == gradient;

  @override
  int get hashCode => Object.hash(path, dim, gradient);
}

/// Фон экрана текстов: PNG/JPG/WebP/GIF (гифка анимируется), поверх —
/// затемнение или градиент. Файл копируется в `<root>/backgrounds`.
class LyricsBackgroundController extends Notifier<LyricsBackground> {
  Directory get _dir =>
      Directory(p.join(ref.read(storageProvider).root.path, 'backgrounds'));

  @override
  LyricsBackground build() {
    final s = ref.read(settingsProvider);
    final name = s.lyricsBgFile;
    String? path;
    if (name != null) {
      final file = File(p.join(_dir.path, name));
      if (file.existsSync()) path = file.path;
    }
    return LyricsBackground(
      path: path,
      dim: s.lyricsBgDim,
      gradient: s.lyricsBgGradient,
    );
  }

  /// Выбор файла. Возвращает `false`, если пользователь отказался.
  Future<bool> pick() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: lyricsBgExtensions,
      dialogTitle: 'Фон экрана текста',
    );
    final source = picked?.path;
    if (source == null) return false;

    final ext = p.extension(source).toLowerCase();
    await _dir.create(recursive: true);
    final target = File(p.join(
      _dir.path,
      'bg_${DateTime.now().millisecondsSinceEpoch}$ext',
    ));
    await File(source).copy(target.path);

    await _deleteOld();
    ref.read(settingsProvider).lyricsBgFile = p.basename(target.path);
    state = LyricsBackground(
      path: target.path,
      dim: state.dim,
      gradient: state.gradient,
    );
    return true;
  }

  Future<void> clear() async {
    await _deleteOld();
    ref.read(settingsProvider).lyricsBgFile = null;
    state = LyricsBackground(dim: state.dim, gradient: state.gradient);
  }

  Future<void> _deleteOld() async {
    final old = state.path;
    if (old == null) return;
    try {
      final file = File(old);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void setDim(double value) {
    ref.read(settingsProvider).lyricsBgDim = value;
    state = state.copyWith(dim: value);
  }

  void setGradient(bool value) {
    ref.read(settingsProvider).lyricsBgGradient = value;
    state = state.copyWith(gradient: value);
  }
}

final lyricsBackgroundProvider =
    NotifierProvider<LyricsBackgroundController, LyricsBackground>(
  LyricsBackgroundController.new,
);
