import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/spotify_link.dart';

void main() {
  const id = '37i9dQZF1DXcBWIGoYBM5M';

  group('parseSpotifyLink', () {
    test('web playlist link with tracking query', () {
      expect(
        parseSpotifyLink('https://open.spotify.com/playlist/$id?si=abc'),
        const SpotifyLink(SpotifyKind.playlist, id),
      );
    });

    test('localized album link', () {
      expect(
        parseSpotifyLink('https://open.spotify.com/intl-ru/album/$id'),
        const SpotifyLink(SpotifyKind.album, id),
      );
    });

    test('uri form and embed form', () {
      expect(parseSpotifyLink('spotify:track:$id'), const SpotifyLink(SpotifyKind.track, id));
      expect(
        parseSpotifyLink('https://open.spotify.com/embed/playlist/$id'),
        const SpotifyLink(SpotifyKind.playlist, id),
      );
    });

    test('bare id is a playlist, garbage is null', () {
      expect(parseSpotifyLink(id), const SpotifyLink(SpotifyKind.playlist, id));
      expect(parseSpotifyLink(''), isNull);
      expect(parseSpotifyLink('https://example.com/playlist'), isNull);
    });
  });
}
