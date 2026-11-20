import 'package:flutter_test/flutter_test.dart';

import 'package:ysplayer/core/utils/lrc_parser.dart';
import 'package:ysplayer/data/models/track.dart';

void main() {
  group('Track', () {
    test('round-trips through json', () {
      const track = Track(
        id: 'abc',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 187),
        thumbnailUrl: 'https://example.com/cover.jpg',
        explicit: true,
        source: TrackSource.local,
        bitrate: 256,
      );

      final restored = Track.fromJson(track.toJson());
      expect(restored.id, 'abc');
      expect(restored.title, 'Title');
      expect(restored.duration, const Duration(seconds: 187));
      expect(restored.explicit, isTrue);
      expect(restored.source, TrackSource.local);
      expect(restored.bitrate, 256);
    });

    test('copyWith keeps unrelated fields', () {
      const track = Track(id: 'a', title: 'T', artist: 'A');
      final updated = track.copyWith(streamUrl: 'https://cdn/audio.m4a');
      expect(updated.streamUrl, 'https://cdn/audio.m4a');
      expect(updated.title, 'T');
      expect(updated.source, TrackSource.youtube);
    });

    test('equality is id based', () {
      const a = Track(id: 'x', title: 'One', artist: 'A');
      const b = Track(id: 'x', title: 'Two', artist: 'B');
      expect(a, b);
    });
  });

  group('LrcParser', () {
    test('detects untimed plain text', () {
      final lyrics = LrcParser.parse('Просто текст\nбез таймкодов');
      expect(lyrics.synced, isFalse);
      expect(lyrics.plainText, contains('Просто текст'));
    });

    test('clamps index before first timestamp', () {
      final lyrics = LrcParser.parse('[00:05.00]Later\n[00:10.00]Next');
      expect(lyrics.indexAt(Duration.zero), 0);
      expect(lyrics.indexAt(const Duration(seconds: 6)), 0);
      expect(lyrics.indexAt(const Duration(seconds: 30)), 1);
    });
  });
}
