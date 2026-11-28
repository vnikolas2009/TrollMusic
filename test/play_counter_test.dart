import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/play_counter.dart';

/// Проигрывает [seconds] секунд подряд с шагом 0,5 с, начиная с [from].
Duration play(PlayCounter c, Duration from, int seconds, {bool playing = true}) {
  var pos = from;
  for (var i = 0; i < seconds * 2; i++) {
    c.tick(pos, playing: playing);
    pos += const Duration(milliseconds: 500);
  }
  return pos;
}

void main() {
  test('порог: 30 секунд, у коротких треков — половина, но не меньше 5 с', () {
    expect(PlayCounter.threshold(const Duration(minutes: 3)), const Duration(seconds: 30));
    expect(PlayCounter.threshold(const Duration(seconds: 40)), const Duration(seconds: 20));
    expect(PlayCounter.threshold(const Duration(seconds: 4)), const Duration(seconds: 5));
    expect(PlayCounter.threshold(null), const Duration(seconds: 30));
  });

  test('засчитывается один раз после 30 секунд', () {
    final counted = <String>[];
    final c = PlayCounter(onPlay: counted.add)..startTrack('a', const Duration(minutes: 3));
    play(c, Duration.zero, 29);
    expect(counted, isEmpty);
    play(c, const Duration(seconds: 29), 40);
    expect(counted, ['a']);
  });

  test('повторное уведомление о том же треке не сбрасывает счёт', () {
    final counted = <String>[];
    final c = PlayCounter(onPlay: counted.add)..startTrack('a', const Duration(minutes: 3));
    final pos = play(c, Duration.zero, 20);
    c.startTrack('a', const Duration(minutes: 3));
    play(c, pos, 15);
    expect(counted, ['a']);
  });

  test('быстрый пропуск не считается', () {
    final counted = <String>[];
    final c = PlayCounter(onPlay: counted.add)..startTrack('a', const Duration(minutes: 3));
    play(c, Duration.zero, 5);
    c.startTrack('b', const Duration(minutes: 3));
    play(c, Duration.zero, 5);
    expect(counted, isEmpty);
  });

  test('перемотка и пауза не накручивают время', () {
    final counted = <String>[];
    final c = PlayCounter(onPlay: counted.add)..startTrack('a', const Duration(minutes: 3));
    // перемотка вперёд скачками по 60 секунд
    for (var s = 0; s < 600; s += 60) {
      c.tick(Duration(seconds: s), playing: true);
    }
    // пауза: позиция идёт, но не играет
    play(c, const Duration(seconds: 10), 60, playing: false);
    expect(counted, isEmpty);
  });

  test('повтор одного трека после конца засчитывается заново', () {
    final counted = <String>[];
    final c = PlayCounter(onPlay: counted.add)..startTrack('a', const Duration(seconds: 40));
    final end = play(c, Duration.zero, 21);
    expect(counted, ['a']);
    c.tick(const Duration(seconds: 39, milliseconds: 500), playing: true);
    c.tick(const Duration(milliseconds: 100), playing: true);
    play(c, const Duration(milliseconds: 600), 21);
    expect(end, isNotNull);
    expect(counted, ['a', 'a']);
  });
}
