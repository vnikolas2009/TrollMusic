import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('mirror timeout is aggressive for fallback', () {
      expect(AppConfig.mirrorTimeout.inSeconds, lessThanOrEqualTo(5));
    });

    test('bitrates are sorted ascending', () {
      final bitrates = AppConfig.audioBitrates;
      for (var i = 1; i < bitrates.length; i++) {
        expect(bitrates[i], greaterThan(bitrates[i - 1]));
      }
      expect(bitrates, contains(AppConfig.defaultBitrate));
    });

    test('default instances are https', () {
      for (final origin in [
        ...AppConfig.defaultPipedInstances,
        ...AppConfig.defaultInvidiousInstances,
      ]) {
        expect(origin.startsWith('https://'), isTrue, reason: origin);
      }
    });
  });
}

