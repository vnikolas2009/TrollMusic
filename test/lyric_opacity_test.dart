import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/features/lyrics/lyrics_screen.dart';

void main() {
  group('lyricLineOpacity', () {
    test('текущая строка полностью яркая', () {
      expect(lyricLineOpacity(0), 1.0);
    });

    test('пройденные ярче будущих на одинаковом расстоянии', () {
      for (var d = 1; d <= 6; d++) {
        expect(lyricLineOpacity(-d), greaterThan(lyricLineOpacity(d)));
      }
    });

    test('с расстоянием тускнеет, но не исчезает', () {
      expect(lyricLineOpacity(1), greaterThan(lyricLineOpacity(20)));
      expect(lyricLineOpacity(-1), greaterThan(lyricLineOpacity(-20)));
      expect(lyricLineOpacity(20), greaterThanOrEqualTo(0.24));
      expect(lyricLineOpacity(-20), greaterThanOrEqualTo(0.3));
    });
  });
}
