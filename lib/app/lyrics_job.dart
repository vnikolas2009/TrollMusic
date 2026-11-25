import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import 'providers.dart';

/// Состояние пакетного поиска текстов.
class LyricsJob {
  const LyricsJob({
    this.total = 0,
    this.done = 0,
    this.found = 0,
    this.running = false,
    this.current,
  });

  final int total;
  final int done;
  final int found;
  final bool running;

  /// Название трека, который обрабатывается сейчас.
  final String? current;

  /// Задача уже запускалась и завершилась (есть итог для показа).
  bool get finished => !running && total > 0;

  double get progress => total == 0 ? 0 : done / total;
}

/// Ищет тексты для треков без текста: до трёх запросов параллельно.
class LyricsJobController extends Notifier<LyricsJob> {
  bool _cancel = false;

  @override
  LyricsJob build() => const LyricsJob();

  /// Все треки медиатеки, у которых ещё нет текста.
  Future<void> runMissing() => run(ref.read(libraryProvider).tracks);

  Future<void> run(Iterable<Track> tracks) async {
    if (state.running) return;
    final library = ref.read(libraryProvider);
    final importer = ref.read(importProvider);

    final queue = tracks.where((t) => !library.hasLyrics(t.id)).toList();
    if (queue.isEmpty) return;

    _cancel = false;
    var cursor = 0;
    var done = 0;
    var found = 0;
    state = LyricsJob(total: queue.length, running: true);

    Future<void> worker() async {
      while (!_cancel && cursor < queue.length) {
        final track = queue[cursor++];
        state = LyricsJob(
          total: queue.length,
          done: done,
          found: found,
          running: true,
          current: track.title,
        );
        try {
          final result = await importer.findLyricsOnline(track);
          if (result.found) found++;
        } catch (_) {}
        done++;
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    state = LyricsJob(total: queue.length, done: done, found: found);
  }

  void cancel() => _cancel = true;

  void clear() {
    if (!state.running) state = const LyricsJob();
  }
}

final lyricsJobProvider =
    NotifierProvider<LyricsJobController, LyricsJob>(LyricsJobController.new);
