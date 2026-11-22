import '../../core/network/soundcloud/soundcloud_service.dart';
import '../../core/network/youtube/innertube_service.dart';
import '../../core/utils/track_match.dart';
import '../../data/models/track.dart';

/// Единая точка получения аудиопотока.
///
/// Порядок: локальный файл → уже известный `streamUrl` → SoundCloud
/// (прямой MP3/HLS, дешевле и стабильнее) → InnerTube (`ANDROID_VR`/`IOS`).
class AudioResolverService {
  AudioResolverService({
    required SoundCloudService soundcloud,
    required InnerTubeService innerTube,
  })  : _soundcloud = soundcloud,
        _innerTube = innerTube;

  final SoundCloudService _soundcloud;
  final InnerTubeService _innerTube;

  /// Ссылки живут ограниченно (подпись в URL), поэтому кэш только на сессию.
  final Map<String, List<String>> _cache = {};
  final Map<String, Future<List<String>>> _inflight = {};

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Несколько кандидатов: плеер переключается на следующий при ошибке.
  Future<List<String>> resolve(Track track) {
    final local = track.localPath;
    if (local != null && local.isNotEmpty) return Future.value(const []);

    final cached = _cache[track.id];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);

    return _inflight[track.id] ??= _resolve(track).then((urls) {
      if (urls.isNotEmpty) _cache[track.id] = urls;
      return urls;
    }).whenComplete(() {
      _inflight.remove(track.id);
    });
  }

  Future<String?> resolveTrackUrl(Track track) async {
    final urls = await resolve(track);
    return urls.isEmpty ? null : urls.first;
  }

  /// Заголовки нужны только для googlevideo (SoundCloud их отклоняет).
  Map<String, String> streamHeaders(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.contains('googlevideo.com') || host.contains('youtube.com')) {
      return InnerTubeService.androidVrStreamHeaders;
    }
    return const {};
  }

  Future<List<Track>> searchSoundCloud(String query, {int limit = 30}) =>
      _soundcloud.search(query, limit: limit).catchError((_) => const <Track>[]);

  Future<List<Track>> searchYouTube(String query, {int limit = 30}) =>
      _innerTube.search(query, limit: limit).catchError((_) => const <Track>[]);

  /// Тренды для пустой медиатеки: сначала YouTube, затем SoundCloud.
  Future<List<Track>> trending() async {
    final youtube = await searchYouTube('популярная музыка 2026');
    if (youtube.isNotEmpty) return youtube;
    return searchSoundCloud('популярная музыка');
  }

  void forget(String trackId) => _cache.remove(trackId);

  Future<List<String>> _resolve(Track track) async {
    final known = (track.streamUrl ?? '').trim();
    if (known.isNotEmpty) return [known];

    final urls = <String>[];

    // 1. SoundCloud напрямую или по совпадению метаданных.
    final soundCloudUrl = await _soundcloud.streamFor(track);
    if (soundCloudUrl != null && soundCloudUrl.isNotEmpty) {
      urls.add(soundCloudUrl);
    }

    // 2. InnerTube: для YouTube-трека берём videoId, иначе ищем по метаданным.
    if (urls.isEmpty) {
      final videoId = track.source == TrackSource.youtube && _videoId.hasMatch(track.id)
          ? track.id
          : await _findVideoId(track);
      if (videoId != null) {
        urls.addAll(await _innerTube.audioUrls(videoId).catchError(
              (_) => const <String>[],
            ));
      }
    }

    return _dedupe(urls);
  }

  Future<String?> _findVideoId(Track track) async {
    final artist = track.artist.split(',').first.trim();
    final queries = <String>[
      '$artist ${track.title}'.trim(),
      '${track.title} $artist'.trim(),
      '${track.title} audio'.trim(),
    ];
    for (final query in queries) {
      if (query.isEmpty) continue;
      final candidates = await searchYouTube(query);
      if (candidates.isEmpty) continue;
      final best = pickBestMatch(track, candidates);
      if (best != null) return best.id;
    }
    return null;
  }

  List<String> _dedupe(Iterable<String> input) {
    final seen = <String>{};
    return [
      for (final url in input)
        if (url.isNotEmpty && seen.add(url)) url,
    ];
  }
}
