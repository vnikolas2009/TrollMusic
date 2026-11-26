import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fonts/font_service.dart';
import 'providers.dart';
import 'settings_provider.dart';

@immutable
class FontState {
  const FontState({required this.fonts, required this.selectedId});

  final List<UserFont> fonts;

  /// Идентификатор выбранного шрифта; `null` — стандартный.
  final String? selectedId;

  UserFont? get selected {
    for (final font in fonts) {
      if (font.id == selectedId) return font;
    }
    return null;
  }

  /// Семейство для темы; `null` — стандартный шрифт.
  String? get family => selected?.family;
}

/// Выбор шрифта: стандартный или импортированный. Сохраняется в
/// настройках и применяется сразу.
class FontController extends Notifier<FontState> {
  FontService get _service => FontService(
        settings: ref.read(settingsProvider),
        root: ref.read(storageProvider).root,
      );

  FontState _read() {
    final service = _service;
    final fonts = service.fonts;
    final id = ref.read(settingsProvider).fontId;
    return FontState(
      fonts: fonts,
      selectedId: fonts.any((f) => f.id == id) ? id : null,
    );
  }

  @override
  FontState build() => _read();

  /// Проверяет файл и готовит предпросмотр. Бросает [FontImportException].
  Future<PendingFont> prepare(String path) => _service.prepare(path);

  /// Добавляет проверенный шрифт и делает его текущим.
  Future<void> addAndSelect(PendingFont pending) async {
    final font = await _service.add(pending);
    ref.read(settingsProvider).fontId = font.id;
    state = _read();
  }

  void select(String? id) {
    ref.read(settingsProvider).fontId = id;
    state = _read();
  }

  /// Возвращает стандартный шрифт.
  void reset() => select(null);

  Future<void> remove(String id) async {
    await _service.remove(id);
    state = _read();
  }
}

final fontControllerProvider =
    NotifierProvider<FontController, FontState>(FontController.new);
