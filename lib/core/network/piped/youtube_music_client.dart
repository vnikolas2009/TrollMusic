import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../../utils/track_match.dart';
import '../youtube/innertube_client.dart';
import 'invidious_client.dart';
import 'piped_client.dart';

class YouTubeMusicClient {
  YouTubeMusicClient({
    required PipedClient piped,
    required InvidiousClient invidious,
    required Settings settings,
  })  : _piped = piped,
        _invidious = invidious,
        _settings = settings,
        _innerTube = InnerTubeClient(settings: settings);

  final PipedClient _piped;
  final InvidiousClient _invidious;
  final Settings _settings;
  final InnerTubeClient _innerTube;

  Future<List<Track>> search(String query) async {
    try {
      final tracks = await _piped.search(query);
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    try {
      final tracks = await _invidious.search(query);
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    try {
      return await _innerTube.search(query);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Track>> trending() async {
    try {
      final tracks = await _piped.trending();
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    try {
      final tracks = await _invidious.trending();
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}
    try {
      return await _innerTube.search('популярная музыка 2026', limit: 30);
    } catch (_) {
      return const [];
    }
  }

  /// Основной резолвер для плеера: возвращает несколько кандидатов URL.
  ///
  /// Spotify-треки не имеют прямого аудио (DRM), поэтому для них подбирается
  /// соответствующий ролик на YouTube по названию и исполнителю.
  Future<List<String>> resolveAudioUrls(Track track) async {
    final local = track.localPath;
    if (local != null && local.isNotEmpty) return const [];

    if (track.source == TrackSource.spotify) {
      return _resolveSpotify(track);
    }

    final urls = <String>[];
    if (track.streamUrl != null && track.streamUrl!.isNotEmpty) {
      urls.add(track.streamUrl!);
    }
    urls.addAll(await _urlsForId(track.id));
    return _dedupe(urls);
  }

  Future<List<String>> _resolveSpotify(Track track) async {
    final queries = <String>[
      '${track.artist.split(',').first} ${track.title}'.trim(),
      '${track.title} ${track.artist}'.trim(),
      '${track.title} audio'.trim(),
    ];
    for (final query in queries) {
      List<Track> candidates;
      try {
        candidates = await search(query);
      } catch (_) {
        continue;
      }
      final best = pickBestMatch(track, candidates);
      final ordered = <Track>[
        if (best != null) best,
        ...candidates.where((c) => c.id != best?.id).take(4),
      ];
      for (final candidate in ordered) {
        final urls = await _urlsForId(candidate.id);
        if (urls.isNotEmpty) {
          _matched[track.id] = candidate.id;
          return urls;
        }
      }
    }
    return const [];
  }

  Future<List<String>> _urlsForId(String videoId) async {
    try {
      final urls = await _piped.resolveStreamUrls(videoId);
      if (urls.isNotEmpty) return urls;
    } catch (_) {}
    try {
      final urls = await _invidious.audioUrls(videoId);
      if (urls.isNotEmpty) return urls;
    } catch (_) {}
    try {
      return await _innerTube.audioUrls(videoId);
    } catch (_) {
      return const [];
    }
  }

  Future<String?> streamUrl(String videoId) async {
    final urls = await _urlsForId(videoId);
    return urls.isEmpty ? null : urls.first;
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
    final urls = await resolveAudioUrls(track);
    return urls.isEmpty ? track : track.copyWith(streamUrl: urls.first);
  }

  /// Заголовки для аудиопотока (помогают ExoPlayer/AVPlayer с googlevideo).
  Map<String, String> get streamHeaders => {
        'User-Agent': 'com.google.android.youtube/19.44.38 (Linux; U; Android 11) gzip',
        'Referer': 'https://www.youtube.com/',
        'Origin': 'https://www.youtube.com',
        'Accept': '*/*',
        ..._settings.requestHeaders,
      };

  List<String> _dedupe(List<String> input) {
    final seen = <String>{};
    return [
      for (final url in input)
        if (url.isNotEmpty && seen.add(url)) url,
    ];
  }
}
