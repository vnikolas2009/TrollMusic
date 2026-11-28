import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/lrc_parser.dart';
import '../core/utils/translation.dart';
import '../services/lyrics/translation_service.dart';
import 'providers.dart';
import 'settings_provider.dart';

@immutable
class TranslationPrefs {
  const TranslationPrefs({this.enabled = false, this.lang = 'ru'});

  final bool enabled;
  final String lang;

  @override
  bool operator ==(Object other) =>
      other is TranslationPrefs && other.enabled == enabled && other.lang == lang;

  @override
  int get hashCode => Object.hash(enabled, lang);
}

/// Включён ли перевод и на какой язык. Сохраняется в настройках.
class TranslationPrefsController extends Notifier<TranslationPrefs> {
  @override
  TranslationPrefs build() {
    final s = ref.read(settingsProvider);
    return TranslationPrefs(enabled: s.translationEnabled, lang: s.translationLang);
  }

  void setEnabled(bool value) {
    ref.read(settingsProvider).translationEnabled = value;
    state = TranslationPrefs(enabled: value, lang: state.lang);
  }

  void setLang(String code) {
    ref.read(settingsProvider).translationLang = code;
    state = TranslationPrefs(enabled: state.enabled, lang: code);
  }
}

final translationPrefsProvider =
    NotifierProvider<TranslationPrefsController, TranslationPrefs>(
  TranslationPrefsController.new,
);

final translationServiceProvider = Provider<TranslationService>(
  (ref) => TranslationService(root: ref.watch(storageProvider).root),
);

/// Перевод текста трека на выбранный язык (`null`, пока перевод выключен или
/// у трека нет текста). Сначала кэш на диске, потом сеть.
///
/// Автоповтор Riverpod 3 отключён: при ошибке сети он молча перезапускал
/// запрос с задержкой, индикатор крутился бесконечно, а сообщение об ошибке
/// не показывалось. Повтор — повторное нажатие кнопки перевода.
final lyricsTranslationProvider = FutureProvider.autoDispose
    .family<TranslationResult?, String>(retry: (_, __) => null, (ref, trackId) async {
  final prefs = ref.watch(translationPrefsProvider);
  if (!prefs.enabled) return null;

  final raw = ref.watch(libraryProvider).lyricsFor(trackId);
  if (raw == null || raw.trim().isEmpty) return null;

  final source = translationSourceLines(LrcParser.parse(raw), raw);
  if (source.every((e) => e.trim().isEmpty)) return null;

  return ref.read(translationServiceProvider).translate(trackId, source, prefs.lang);
});
