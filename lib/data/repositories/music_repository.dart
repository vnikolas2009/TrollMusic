import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../../core/network/lyrics/lyrics_client.dart';
import '../../core/network/piped/youtube_music_client.dart';
import '../../core/network/spotify/spotify_client.dart';

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
      if (spotify.hasCredentials) _safeList(spotify.search(query)),
    ]);

    final seen = <String>{};
    return [
      for (final tracks in responses)
        for (final track in tracks)
          if (seen.add('${track.source.name}:${track.id}')) track,
    ];
  }

  Future<List<Track>> searchYouTube(String query) => youtube.search(query);

  Future<Playlist?> spotifyPlaylist(String url) async {
    final id = parseSpotifyId(url);
    if (id == null) return null;
    return spotify.playlist(id);
  }

  Future<Lyrics?> findLyrics(Track track) =>
      lyrics.get(title: track.title, artist: track.artist, album: track.album);

  String? parseSpotifyId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final spotifyUri =
        RegExp(r'spotify:(?:playlist|album|track):([A-Za-z0-9]+)').firstMatch(trimmed);
    if (spotifyUri != null) return spotifyUri.group(1);

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final segments = uri.pathSegments;
      final idx = segments.indexWhere(
        (s) => s == 'playlist' || s == 'album' || s == 'track',
      );
      if (idx >= 0 && idx + 1 < segments.length) {
        return segments[idx + 1].split('?').first;
      }
    }

    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(trimmed)) return trimmed;
    return null;
  }

  Future<List<Track>> _safeList(Future<List<Track>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }
}
