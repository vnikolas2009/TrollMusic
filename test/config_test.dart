import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('bitrates are sorted ascending', () {
      final bitrates = AppConfig.audioBitrates;
      for (var i = 1; i < bitrates.length; i++) {
        expect(bitrates[i], greaterThan(bitrates[i - 1]));
      }
      expect(bitrates, contains(AppConfig.defaultBitrate));
    });

    test('DoH endpoints are https', () {
      expect(AppConfig.dohEndpoints, isNotEmpty);
      for (final endpoint in AppConfig.dohEndpoints) {
        expect(endpoint.startsWith('https://'), isTrue, reason: endpoint);
      }
    });

    test('default API base is https without trailing slash', () {
      expect(AppConfig.defaultApiBase.startsWith('https://'), isTrue);
      expect(AppConfig.defaultApiBase.endsWith('/'), isFalse);
    });

    test('prefetch window is positive', () {
      expect(AppConfig.prefetchBefore, greaterThan(Duration.zero));
    });
  });
}
