import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Режим тренировки текста: часть слов в строках, которые ещё не спеты,
/// скрыта. Не сохраняется между запусками — включается на время занятия.
class LyricsPracticeController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final lyricsPracticeProvider =
    NotifierProvider<LyricsPracticeController, bool>(LyricsPracticeController.new);
