import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('audio extensions are lowercase without dots', () {
      expect(AppConfig.audioExtensions, isNotEmpty);
      for (final ext in AppConfig.audioExtensions) {
        expect(ext, ext.toLowerCase());
        expect(ext.startsWith('.'), isFalse);
      }
      expect(AppConfig.audioExtensions, containsAll(['mp3', 'flac', 'm4a']));
    });

    test('lyrics extensions include lrc and enhanced lrc', () {
      expect(AppConfig.lyricsExtensions, containsAll(['lrc', 'elrc', 'txt']));
    });

    test('timeouts are positive', () {
      expect(AppConfig.connectTimeout, greaterThan(Duration.zero));
      expect(AppConfig.requestTimeout, greaterThan(Duration.zero));
    });
  });
}
