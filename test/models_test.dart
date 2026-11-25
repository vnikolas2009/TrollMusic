import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/lrc_parser.dart';
import 'package:trollmusic/data/models/track.dart';

void main() {
  group('Track', () {
    test('round-trips through json', () {
      const track = Track(
        id: 'abc',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(seconds: 187),
        localPath: '/music/a.mp3',
        explicit: true,
        bitrate: 256,
        addedAtMs: 10,
      );

      final restored = Track.fromJson(track.toJson());
      expect(restored.id, 'abc');
      expect(restored.title, 'Title');
      expect(restored.duration, const Duration(seconds: 187));
      expect(restored.localPath, '/music/a.mp3');
      expect(restored.explicit, isTrue);
      expect(restored.bitrate, 256);
      expect(restored.addedAtMs, 10);
    });

    test('reads records saved by older streaming versions', () {
      final restored = Track.fromJson({
        'id': 'yt:1',
        'title': 'Old',
        'artist': 'Someone',
        'thumbnailUrl': 'https://example.com/c.jpg',
        'streamUrl': 'https://cdn/a.m4a',
        'source': 'youtube',
        'localPath': '/music/old.mp3',
      });
      expect(restored.title, 'Old');
      expect(restored.localPath, '/music/old.mp3');
    });

    test('copyWith keeps unrelated fields', () {
      const track = Track(id: 'a', title: 'T', artist: 'A');
      final updated = track.copyWith(lyricsPath: '/l/a.lrc');
      expect(updated.lyricsPath, '/l/a.lrc');
      expect(updated.title, 'T');
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
