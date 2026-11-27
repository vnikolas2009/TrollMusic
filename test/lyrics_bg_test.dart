import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/lyrics_bg.dart';

void main() {
  test('ровное затемнение одинаково сверху и снизу', () {
    final s = lyricsBgScrim(0.5, gradient: false);
    expect(s.top, 0.5);
    expect(s.bottom, 0.5);
  });

  test('градиент: верх светлее, низ темнее', () {
    final s = lyricsBgScrim(0.5, gradient: true);
    expect(s.top, closeTo(0.3, 1e-9));
    expect(s.bottom, closeTo(0.9, 1e-9));
    expect(s.top < s.bottom, isTrue);
  });

  test('значения ограничиваются', () {
    expect(lyricsBgScrim(0.0, gradient: false).top, 0.2);
    expect(lyricsBgScrim(2.0, gradient: false).top, 0.9);
    expect(lyricsBgScrim(0.9, gradient: true).bottom, 0.95);
  });
}
