import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/services/download/download_service.dart';

void main() {
  group('DownloadProgress', () {
    test('fraction is received over total', () {
      const progress = DownloadProgress(
        received: 50,
        total: 200,
        state: DownloadState.running,
      );
      expect(progress.fraction, 0.25);
    });

    test('fraction clamps to 1', () {
      const progress = DownloadProgress(
        received: 300,
        total: 200,
        state: DownloadState.running,
      );
      expect(progress.fraction, 1);
    });

    test('unknown total falls back to state', () {
      expect(
        const DownloadProgress(
          received: 10,
          total: 0,
          state: DownloadState.running,
        ).fraction,
        0,
      );
      expect(
        const DownloadProgress(
          received: 0,
          total: 0,
          state: DownloadState.done,
        ).fraction,
        1,
      );
    });
  });
}

