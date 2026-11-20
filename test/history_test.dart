import 'package:flutter_test/flutter_test.dart';

void main() {
  group('history helpers', () {
    test('recent list keeps newest first and removes duplicates', () {
      final recent = <String>[];

      void push(String id) {
        recent.remove(id);
        recent.insert(0, id);
      }

      push('a');
      push('b');
      push('a');
      expect(recent, ['a', 'b']);

      final trimmed = recent.take(100).toList();
      expect(trimmed.length, 2);
    });

    test('play counts accumulate', () {
      final counts = <String, int>{};
      for (final id in ['a', 'a', 'b']) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
      expect(counts['a'], 2);
      expect(counts['b'], 1);
    });
  });
}
