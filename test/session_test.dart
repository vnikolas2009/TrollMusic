import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/session.dart';

void main() {
  group('restoreQueue', () {
    test('всё на месте', () {
      final r = restoreQueue(savedIds: ['a', 'b', 'c'], savedIndex: 1, isAvailable: (_) => true);
      expect(r.ids, ['a', 'b', 'c']);
      expect(r.index, 1);
      expect(r.sameTrack, isTrue);
    });

    test('недоступные треки выбрасываются, индекс сдвигается', () {
      final r = restoreQueue(savedIds: ['a', 'b', 'c', 'd'], savedIndex: 2, isAvailable: (id) => id != 'a');
      expect(r.ids, ['b', 'c', 'd']);
      expect(r.index, 1);
      expect(r.sameTrack, isTrue);
    });

    test('пропал текущий трек: берётся следующий', () {
      final r = restoreQueue(savedIds: ['a', 'b', 'c'], savedIndex: 1, isAvailable: (id) => id != 'b');
      expect(r.ids, ['a', 'c']);
      expect(r.index, 1);
      expect(r.sameTrack, isFalse);
    });

    test('пропали текущий и все следующие: берётся последний', () {
      final r = restoreQueue(savedIds: ['a', 'b', 'c'], savedIndex: 1, isAvailable: (id) => id == 'a');
      expect(r.ids, ['a']);
      expect(r.index, 0);
      expect(r.sameTrack, isFalse);
    });

    test('пусто или всё недоступно', () {
      expect(restoreQueue(savedIds: [], savedIndex: 0, isAvailable: (_) => true).ids, isEmpty);
      expect(restoreQueue(savedIds: ['a'], savedIndex: 0, isAvailable: (_) => false).ids, isEmpty);
    });

    test('индекс за пределами ограничивается', () {
      final r = restoreQueue(savedIds: ['a', 'b'], savedIndex: 9, isAvailable: (_) => true);
      expect(r.index, 1);
    });
  });

  group('trimQueue', () {
    final ids = [for (var i = 0; i < 1000; i++) '$i'];

    test('короткая очередь не меняется', () {
      final r = trimQueue(['a', 'b'], 1);
      expect(r.ids, ['a', 'b']);
      expect(r.index, 1);
    });

    test('длинная обрезается окном вокруг текущего', () {
      final r = trimQueue(ids, 500, max: 100);
      expect(r.ids.length, 100);
      expect(r.ids[r.index], '500');
    });

    test('у краёв окно сдвигается', () {
      final start = trimQueue(ids, 3, max: 100);
      expect(start.ids.first, '0');
      expect(start.ids[start.index], '3');
      final end = trimQueue(ids, 998, max: 100);
      expect(end.ids.last, '999');
      expect(end.ids[end.index], '998');
    });
  });
}
