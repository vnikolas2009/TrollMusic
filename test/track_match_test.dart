import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/track_match.dart';
import 'package:trollmusic/data/models/track.dart';

Track t(String id, String title, String artist, int sec) => Track(
      id: id,
      title: title,
      artist: artist,
      duration: Duration(seconds: sec),
    );

void main() {
  final target = t('sp:1', 'No Trust', 'AQUAKEY', 180);

  test('prefers matching duration and artist over a live version', () {
    final best = pickBestMatch(target, [
      t('a', 'No Trust (Live)', 'AQUAKEY', 300),
      t('b', 'AQUAKEY - No Trust', 'AQUAKEY', 181),
      t('c', 'Other song', 'Someone', 180),
    ]);
    expect(best?.id, 'b');
  });

  test('empty candidates give null, unknown durations keep first match', () {
    expect(pickBestMatch(target, const []), isNull);
    final noDur = t('sp:2', 'Halloween', 'rejiboi', 0);
    expect(
      pickBestMatch(noDur, [t('x', 'halloween', 'rejiboi', 200), t('y', 'zzz', 'q', 1)])?.id,
      'x',
    );
  });
}
