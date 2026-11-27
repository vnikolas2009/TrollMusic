import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/smart_shuffle.dart';
import 'package:trollmusic/data/models/track.dart';

Track t(String id, String artist) => Track(
      id: id,
      title: id,
      artist: artist,
      album: '',
      duration: const Duration(minutes: 3),
    );

void main() {
  test('вес: недавние тяжелее штрафуются, редкие получают бонус', () {
    expect(shuffleWeight(recentRank: 0) < shuffleWeight(recentRank: 20), isTrue);
    expect(shuffleWeight(recentRank: 20) < shuffleWeight(recentRank: 50), isTrue);
    expect(shuffleWeight(recentRank: 50) < shuffleWeight(), isTrue);
    expect(shuffleWeight(playCount: 0) > shuffleWeight(playCount: 20), isTrue);
  });

  test('каждый трек встречается ровно один раз', () {
    final tracks = [for (var i = 0; i < 30; i++) t('t$i', 'a${i % 5}')];
    final out = smartShuffle(tracks, recentIds: const [], playCounts: const {}, random: Random(1));
    expect(out.map((e) => e.id).toSet().length, 30);
    expect(out.length, 30);
  });

  test('один и тот же seed даёт один порядок', () {
    final tracks = [for (var i = 0; i < 12; i++) t('t$i', 'a$i')];
    final a = smartShuffle(tracks, recentIds: const [], playCounts: const {}, random: Random(7));
    final b = smartShuffle(tracks, recentIds: const [], playCounts: const {}, random: Random(7));
    expect(a.map((e) => e.id), b.map((e) => e.id));
  });

  test('только что игравший трек в среднем оказывается дальше', () {
    final tracks = [for (var i = 0; i < 20; i++) t('t$i', 'a$i')];
    var sumRecent = 0;
    var sumOther = 0.0;
    const runs = 300;
    for (var s = 0; s < runs; s++) {
      final out = smartShuffle(tracks, recentIds: const ['t0'], playCounts: const {}, random: Random(s));
      sumRecent += out.indexWhere((e) => e.id == 't0');
      sumOther += out.indexWhere((e) => e.id == 't1');
    }
    expect(sumRecent / runs, greaterThan(sumOther / runs + 3));
  });

  test('одинаковые исполнители не стоят подряд, если можно развести', () {
    final tracks = [
      for (var i = 0; i < 10; i++) t('x$i', 'X'),
      for (var i = 0; i < 10; i++) t('y$i', 'Y'),
    ];
    for (var s = 0; s < 20; s++) {
      final out = smartShuffle(tracks, recentIds: const [], playCounts: const {}, random: Random(s));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].artist == out[i - 1].artist, isFalse, reason: 'seed $s, позиция $i');
      }
    }
  });

  test('если остался один исполнитель, порядок не ломается', () {
    final tracks = [for (var i = 0; i < 5; i++) t('x$i', 'X')];
    final out = smartShuffle(tracks, recentIds: const [], playCounts: const {}, random: Random(2));
    expect(out.length, 5);
  });
}
