import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/formatters.dart';

void main() {
  group('formatRemaining', () {
    test('оставшееся время со знаком минус', () {
      expect(
        formatRemaining(const Duration(seconds: 49), const Duration(minutes: 3, seconds: 20)),
        '-2:31',
      );
    });

    test('в конце трека — ноль, а не плюс', () {
      expect(formatRemaining(const Duration(minutes: 4), const Duration(minutes: 3)), '-0:00');
      expect(formatRemaining(const Duration(minutes: 3), const Duration(minutes: 3)), '-0:00');
    });
  });
}
