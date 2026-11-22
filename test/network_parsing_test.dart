import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/network/doh_resolver.dart';
import 'package:trollmusic/core/network/soundcloud/soundcloud_service.dart' as sc;
import 'package:trollmusic/core/network/youtube/innertube_service.dart' as yt;
import 'package:trollmusic/data/models/track.dart';

void main() {
  group('DohResolver.parseDohResponse', () {
    test('keeps only A records and reads TTL', () {
      final body = jsonEncode({
        'Answer': [
          {'type': 5, 'data': 'alias.example.com.', 'TTL': 10},
          {'type': 1, 'data': '93.184.216.34', 'TTL': 120},
        ],
      });
      final result = DohResolver.parseDohResponse(body);
      expect(result.addresses.map((a) => a.address), ['93.184.216.34']);
      expect(result.ttl, 120);
    });

    test('empty answer gives no addresses', () {
      final result = DohResolver.parseDohResponse('{"Status":3}');
      expect(result.addresses, isEmpty);
    });
  });

  group('SoundCloud parsing', () {
    test('parseSearchBody maps tracks and skips non-streamable', () {
      final body = jsonEncode({
        'collection': [
          {
            'kind': 'track',
            'id': 42,
            'title': 'Song',
            'duration': 185000,
            'artwork_url': 'https://i1.sndcdn.com/a-large.jpg',
            'user': {'username': 'Artist'},
          },
          {'kind': 'track', 'id': 43, 'title': 'Blocked', 'streamable': false},
          {'kind': 'user', 'id': 44},
        ],
      });
      final tracks = sc.parseSearchBody(body);
      expect(tracks, hasLength(1));
      expect(tracks.first.id, 'sc:42');
      expect(tracks.first.artist, 'Artist');
      expect(tracks.first.duration, const Duration(milliseconds: 185000));
      expect(tracks.first.source, TrackSource.soundcloud);
    });

    test('parseTranscodings puts progressive before HLS', () {
      final body = jsonEncode({
        'track_authorization': 'auth',
        'media': {
          'transcodings': [
            {
              'url': 'https://api/hls',
              'format': {'protocol': 'hls', 'mime_type': 'audio/mpeg'},
            },
            {
              'url': 'https://api/prog',
              'format': {'protocol': 'progressive', 'mime_type': 'audio/mpeg'},
            },
          ],
        },
      });
      final parsed = sc.parseTranscodings(body);
      expect(parsed.authorization, 'auth');
      expect(parsed.urls, ['https://api/prog', 'https://api/hls']);
    });

    test('parseTranscodings returns nothing for blocked tracks', () {
      final body = jsonEncode({
        'policy': 'BLOCK',
        'media': {
          'transcodings': [
            {
              'url': 'https://api/prog',
              'format': {'protocol': 'progressive', 'mime_type': 'audio/mpeg'},
            },
          ],
        },
      });
      expect(sc.parseTranscodings(body).urls, isEmpty);
    });

    test('pickBest requires a title match', () {
      const target = Track(
        id: 'sp:1',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: Duration(seconds: 200),
        source: TrackSource.spotify,
      );
      const good = Track(
        id: 'sc:1',
        title: 'The Weeknd - Blinding Lights',
        artist: 'Uploader',
        duration: Duration(seconds: 201),
        source: TrackSource.soundcloud,
      );
      const bad = Track(
        id: 'sc:2',
        title: 'Other Song',
        artist: 'The Weeknd',
        duration: Duration(seconds: 200),
        source: TrackSource.soundcloud,
      );
      expect(sc.pickBest(target, [bad, good])?.id, 'sc:1');
      expect(sc.pickBest(target, [bad]), isNull);
    });
  });

  group('InnerTube parsing', () {
    test('parseSearchBody reads videoRenderer', () {
      final body = jsonEncode({
        'contents': [
          {
            'videoRenderer': {
              'videoId': 'abc123',
              'title': {
                'runs': [
                  {'text': 'Title'},
                ],
              },
              'ownerText': {
                'runs': [
                  {'text': 'Channel'},
                ],
              },
              'lengthText': {'simpleText': '3:25'},
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/a.jpg'},
                ],
              },
            },
          },
        ],
      });
      final tracks = yt.parseSearchBody(body);
      expect(tracks, hasLength(1));
      expect(tracks.first.id, 'abc123');
      expect(tracks.first.artist, 'Channel');
      expect(tracks.first.duration, const Duration(minutes: 3, seconds: 25));
    });

    test('parseAudioBody prefers the closest bitrate and appends HLS', () {
      final body = jsonEncode({
        'streamingData': {
          'adaptiveFormats': [
            {'mimeType': 'video/mp4', 'url': 'https://v', 'bitrate': 900000},
            {'mimeType': 'audio/mp4; codecs="mp4a"', 'url': 'https://a128', 'bitrate': 128000},
            {'mimeType': 'audio/mp4; codecs="mp4a"', 'url': 'https://a192', 'bitrate': 192000},
          ],
          'hlsManifestUrl': 'https://hls/manifest.m3u8',
        },
      });
      final urls = yt.parseAudioBody(body, target: 192, preferOpus: false);
      expect(urls.first, 'https://a192');
      expect(urls, isNot(contains('https://v')));
      expect(urls.last, 'https://hls/manifest.m3u8');
    });
  });
}
