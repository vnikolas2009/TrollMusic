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
