import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/sleep_fade.dart';

void main() {
  test('до начала затухания громкость полная', () {
    expect(sleepFadeVolume(const Duration(minutes: 5)), 1);
    expect(sleepFadeVolume(const Duration(seconds: 45)), 1);
  });

  test('затухание линейное', () {
    expect(sleepFadeVolume(const Duration(milliseconds: 22500)), closeTo(0.5, 1e-9));
    expect(sleepFadeVolume(const Duration(seconds: 9), fade: const Duration(seconds: 18)), closeTo(0.5, 1e-9));
  });

  test('в конце тишина, без затухания — как раньше', () {
    expect(sleepFadeVolume(Duration.zero), 0);
    expect(sleepFadeVolume(const Duration(seconds: 3), fade: Duration.zero), 1);
  });
}
