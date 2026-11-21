import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../../core/network/lyrics/lyrics_client.dart';
import '../../core/network/piped/youtube_music_client.dart';
import '../../core/network/spotify/spotify_client.dart';
import '../../core/utils/spotify_link.dart';

class MusicRepository {
  MusicRepository({
    required this.youtube,
    required this.spotify,
    required this.lyrics,
  });

  final YouTubeMusicClient youtube;
  final SpotifyClient spotify;
  final LyricsClient lyrics;

  Future<List<Track>> searchAll(String query) async {
    final responses = await Future.wait([
      _safeList(youtube.search(query)),
      _safeList(spotify.search(query)),
    ]);

    final seen = <String>{};
    return [
      for (final tracks in responses)
        for (final track in tracks)
          if (seen.add('${track.source.name}:${track.id}')) track,
    ];
  }

  Future<List<Track>> searchYouTube(String query) => youtube.search(query);

  Future<List<Track>> searchSpotify(String query) => spotify.search(query);

  /// Подборка Spotify по нескольким запросам (круговое перемешивание, без дублей).
  Future<List<Track>> spotifyMix(List<String> queries, {int limit = 30}) async {
    final results = await Future.wait([
      for (final q in queries) _safeList(spotify.search(q, limit: 15)),
    ]);
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
