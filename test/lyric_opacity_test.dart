import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/lyric_style.dart';

void main() {
  group('LyricsStyle.opacity', () {
    test('текущая строка полностью яркая в любом стиле', () {
      for (final style in LyricsStyle.values) {
        expect(style.opacity(0), 1.0);
      }
    });

    test('остальные строки видны, но тусклее текущей', () {
      for (final style in LyricsStyle.values) {
        for (final d in [-20, -3, -1, 1, 3, 20]) {
          expect(style.opacity(d), inExclusiveRange(0.0, 1.0));
        }
      }
    });

    test('Spotify-like: пройденные ярче будущих, дальние тускнее', () {
      const s = LyricsStyle.spotify;
      for (var d = 1; d <= 6; d++) {
        expect(s.opacity(-d), greaterThan(s.opacity(d)));
      }
      expect(s.opacity(1), greaterThan(s.opacity(20)));
      expect(s.opacity(-1), greaterThan(s.opacity(-20)));
    });
  });

  group('LyricsStyle', () {
    test('по умолчанию Spotify-like', () {
      expect(LyricsStyle.defaultStyle, LyricsStyle.spotify);
      expect(LyricsStyle.fromName(null), LyricsStyle.spotify);
      expect(LyricsStyle.fromName('что-то неизвестное'), LyricsStyle.spotify);
    });

    test('имя сохраняется и читается обратно', () {
      for (final style in LyricsStyle.values) {
        expect(LyricsStyle.fromName(style.name), style);
      }
    });

    test('подсветка по словам только у Spotify-like', () {
      expect(LyricsStyle.spotify.look.wordHighlight, isTrue);
      expect(LyricsStyle.minimal.look.wordHighlight, isFalse);
      expect(LyricsStyle.classic.look.wordHighlight, isFalse);
    });
  });
}
