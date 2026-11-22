import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../../core/network/lyrics/lyrics_client.dart';
import '../../core/network/spotify/spotify_client.dart';
import '../../core/utils/spotify_link.dart';
import '../../services/audio/audio_resolver_service.dart';

class MusicRepository {
  MusicRepository({
    required this.resolver,
    required this.spotify,
    required this.lyrics,
  });

  final AudioResolverService resolver;
  final SpotifyClient spotify;
  final LyricsClient lyrics;

  /// SoundCloud, InnerTube и Spotify опрашиваются параллельно.
  Future<List<Track>> searchAll(String query) async {
    final responses = await Future.wait([
      _safeList(resolver.searchSoundCloud(query)),
      _safeList(resolver.searchYouTube(query)),
      _safeList(spotify.search(query)),
    ]);

    final seen = <String>{};
    return [
      for (final tracks in responses)
        for (final track in tracks)
          if (seen.add('${track.source.name}:${track.id}')) track,
    ];
  }

  Future<List<Track>> searchYouTube(String query) => resolver.searchYouTube(query);

  /// Spotify в приоритете: выдаёт песни по названию. Если Spotify ничего
  /// не вернул — подстраховка песнями YouTube Music.
  Future<List<Track>> searchSpotify(String query) async {
    final tracks = await _safeList(spotify.search(query));
    if (tracks.isNotEmpty) return tracks;
    return _safeList(resolver.searchYouTube(query));
  }

  /// Подборка YouTube по нескольким запросам (круговое перемешивание, без дублей).
  Future<List<Track>> youtubeMix(List<String> queries, {int limit = 30}) async {
    final results = await Future.wait([
      for (final q in queries) _safeList(resolver.searchYouTube(q, limit: 15)),
    ]);
    return _interleave(results, limit);
  }

  /// Подборка Spotify по нескольким запросам (круговое перемешивание, без дублей).
  Future<List<Track>> spotifyMix(List<String> queries, {int limit = 30}) async {
    final results = await Future.wait([
      for (final q in queries) _safeList(spotify.search(q, limit: 15)),
    ]);
    return _interleave(results, limit);
  }

  List<Track> _interleave(List<List<Track>> results, int limit) {
    final out = <Track>[];
    final seen = <String>{};
    for (var round = 0; out.length < limit; round++) {
      var any = false;
      for (final list in results) {
        if (round >= list.length || out.length >= limit) continue;
        any = true;
        final t = list[round];
        if (seen.add('${t.artist}|${t.title}'.toLowerCase())) out.add(t);
      }
      if (!any) break;
    }
    return out;
  }

  Future<Playlist?> spotifyPlaylist(String url) async {
    final link = parseSpotifyLink(url);
    if (link == null || link.kind == SpotifyKind.track) return null;
    return link.kind == SpotifyKind.album
        ? spotify.album(link.id)
        : spotify.playlist(link.id);
  }

  Future<Lyrics?> findLyrics(Track track) =>
      lyrics.get(title: track.title, artist: track.artist, album: track.album);

  String? parseSpotifyId(String input) => parseSpotifyLink(input)?.id;

  Future<List<Track>> _safeList(Future<List<Track>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }
}
