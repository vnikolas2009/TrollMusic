import '../../../data/models/track.dart';
import '../../utils/track_match.dart';
import 'invidious_client.dart';
import 'piped_client.dart';

class YouTubeMusicClient {
  YouTubeMusicClient({required PipedClient piped, required InvidiousClient invidious})
      : _piped = piped,
        _invidious = invidious;

  final PipedClient _piped;
  final InvidiousClient _invidious;

  Future<List<Track>> search(String query) async {
    try {
      final tracks = await _piped.search(query);
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    return _invidious.search(query);
  }

  Future<List<Track>> trending() async {
    try {
      final tracks = await _piped.trending();
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    try {
      return await _invidious.trending();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> streamUrl(String videoId) async {
    try {
      final url = await _piped.resolveStreamUrl(videoId);
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
    try {
      return await _invidious.audioUrl(videoId);
    } catch (_) {
      return null;
    }
  }

  final _matched = <String, String>{};

  /// Поток для любого трека. Для Spotify (`sp:`) сначала находим видео на YouTube
  /// по «исполнитель + название» и запоминаем соответствие на время сессии.
  Future<String?> streamUrlForTrack(Track track) async {
    var videoId = track.id;
    if (track.source == TrackSource.spotify || track.id.startsWith('sp:')) {
      final cached = _matched[track.id];
      if (cached != null) {
        videoId = cached;
      } else {
        try {
          final found = pickBestMatch(
            track,
            await search('${track.artist.split(',').first} ${track.title}'),
          );
          if (found == null) return null;
          videoId = found.id;
          _matched[track.id] = videoId;
        } catch (_) {
          return null;
        }
      }
    }
    return streamUrl(videoId);
  }

  Future<Track> resolveTrack(Track track) async {
    if (track.streamUrl != null) return track;
    final url = await streamUrl(track.id);
    return url == null ? track : track.copyWith(streamUrl: url);
  }
}
