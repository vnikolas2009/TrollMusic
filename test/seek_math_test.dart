import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/seek_math.dart';

void main() {
  const total = Duration(minutes: 3);

  test('fractionOf: границы и неизвестная длительность', () {
    expect(fractionOf(Duration.zero, total), 0);
    expect(fractionOf(const Duration(seconds: 90), total), 0.5);
    expect(fractionOf(const Duration(minutes: 5), total), 1);
    expect(fractionOf(const Duration(seconds: 10), Duration.zero), 0);
  });

  test('fractionForDx обрезает координату по ширине полосы', () {
    expect(fractionForDx(50, 200), 0.25);
    expect(fractionForDx(-30, 200), 0);
    expect(fractionForDx(999, 200), 1);
    expect(fractionForDx(10, 0), 0);
  });

  test('durationForFraction обрезает долю и округляет', () {
    expect(durationForFraction(0.5, total), const Duration(seconds: 90));
    expect(durationForFraction(-1, total), Duration.zero);
    expect(durationForFraction(2, total), total);
    expect(durationForFraction(0.5, Duration.zero), Duration.zero);
  });

  test('shiftPosition не выходит за 0 и за длительность', () {
    expect(
      shiftPosition(const Duration(seconds: 5), const Duration(seconds: -10), total),
      Duration.zero,
    );
    expect(
      shiftPosition(const Duration(seconds: 175), const Duration(seconds: 10), total),
      total,
    );
    expect(
      shiftPosition(const Duration(seconds: 30), const Duration(seconds: 10), total),
      const Duration(seconds: 40),
    );
    // длительность неизвестна: верхней границы нет
    expect(
      shiftPosition(const Duration(seconds: 30), const Duration(seconds: 10), Duration.zero),
      const Duration(seconds: 40),
    );
  });
}
