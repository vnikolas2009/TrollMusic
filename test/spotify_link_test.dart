import 'package:flutter_test/flutter_test.dart';

import 'package:ysplayer/core/utils/proxy_address.dart';
import 'package:ysplayer/core/utils/spotify_link.dart';

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

  group('normalizeProxyAddress', () {
    test('accepts host:port and strips scheme/path', () {
      expect(normalizeProxyAddress(' 127.0.0.1:8080 '), '127.0.0.1:8080');
      expect(normalizeProxyAddress('http://proxy.local:3128/'), 'proxy.local:3128');
      expect(normalizeProxyAddress('http://user:pass@10.0.0.2:8000'), '10.0.0.2:8000');
    });

    test('rejects empty, socks, bad port', () {
      expect(normalizeProxyAddress(''), '');
      expect(normalizeProxyAddress('socks5://127.0.0.1:1080'), '');
      expect(normalizeProxyAddress('host:99999'), '');
      expect(normalizeProxyAddress('host'), '');
    });
  });
}
