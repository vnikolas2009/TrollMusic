import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/lyric_style.dart';
import 'settings_provider.dart';

/// Выбранный стиль текстов песен. Сохраняется в настройках и применяется
/// на экране текстов сразу.
class LyricsStyleController extends Notifier<LyricsStyle> {
  @override
  LyricsStyle build() =>
      LyricsStyle.fromName(ref.read(settingsProvider).lyricsStyle);

  void set(LyricsStyle style) {
    ref.read(settingsProvider).lyricsStyle = style.name;
    state = style;
  }
}

final lyricsStyleProvider =
    NotifierProvider<LyricsStyleController, LyricsStyle>(
  LyricsStyleController.new,
);
