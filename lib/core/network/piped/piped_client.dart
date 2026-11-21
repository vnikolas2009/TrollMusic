import '../../../data/models/track.dart';
import '../../network/http_client.dart';
import '../../network/mirror_manager.dart';
import '../../network/proxy.dart';
import '../../network/worker_health.dart';
import '../../storage/settings.dart';

class PipedClient {
  PipedClient({
    required Settings settings,
    required ProxyConfig proxy,
    WorkerHealth? health,
  })  : _settings = settings,
        _proxy = proxy,
        _health = health {
    _mirrors = MirrorManager(
      settings: settings,
      dio: createDio(settings: settings),
      health: health,
    );
  }

  final Settings _settings;
  final ProxyConfig _proxy;
  final WorkerHealth? _health;
  late final MirrorManager _mirrors;

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final data = await _json(MirrorKind.piped, '/search', {
      'q': query,
      'filter': 'music_songs',
    });
    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .where((e) => e['type'] == 'stream' || e['url'] != null)
        .take(limit)
        .map(_toTrack)
        .toList();
  }

  Future<List<Track>> artistTracks(String channelId, {int limit = 50}) async {
    final data = await _json(MirrorKind.piped, '/channel/$channelId', const {});
    final items = (data['relatedStreams'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map(_toTrack)
        .toList();
  }

  Future<Track> stream(String videoId) async {
    final data = await _json(MirrorKind.piped, '/streams/$videoId', const {});
    final track = _toTrack(<String, dynamic>{'url': '/watch?v=$videoId', ...data});
    final url = _pickAudioUrl(data);
    return track.copyWith(streamUrl: url);
  }

  Future<String?> resolveStreamUrl(String videoId, {int? bitrate}) async {
    final urls = await resolveStreamUrls(videoId, bitrate: bitrate);
    return urls.isEmpty ? null : urls.first;
  }

  /// Несколько кандидатов: проксированный и прямой варианты.
  Future<List<String>> resolveStreamUrls(String videoId, {int? bitrate}) async {
    final data = await _json(MirrorKind.piped, '/streams/$videoId', const {});
    final raw = _pickAudioUrls(data, bitrate: bitrate ?? _settings.bitrate);
    final out = <String>[];
    for (final url in raw) {
      for (final candidate in _variants(url)) {
        if (!out.contains(candidate)) out.add(candidate);
      }
    }
    return out;
  }

  Future<List<Track>> trending({int limit = 30}) async {
    final data = await _json(MirrorKind.piped, '/trending', {'region': 'RU'});
    final items = (data['items'] as List?) ?? const [];
    return items.whereType<Map<String, dynamic>>().take(limit).map(_toTrack).toList();
  }

  Future<Map<String, dynamic>> _json(
    MirrorKind kind,
    String path,
    Map<String, dynamic> query,
  ) async {
    final response = await _mirrors.get(
      kind,
      path,
      query: query.isEmpty ? null : query,
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is List) return {'items': data};
    return const {};
  }

  Track _toTrack(Map<String, dynamic> json) {
    final rawUrl = json['url'] as String? ?? '';
    final videoId = _videoId(rawUrl) ?? (json['id'] as String? ?? '');
    final thumb = json['thumbnail'] as String? ?? json['thumbnailUrl'] as String?;
    return Track(
      id: videoId,
      title: json['title'] as String? ?? 'Без названия',
      artist: json['uploaderName'] as String? ??
          json['uploader'] as String? ??
          json['artist'] as String? ??
          'Неизвестный исполнитель',
      duration: Duration(seconds: _seconds(json['duration'])),
      thumbnailUrl: thumb,
      source: TrackSource.youtube,
      explicit: json['isExplicit'] == true,
    );
  }

  String? _pickAudioUrl(Map<String, dynamic> data, {int? bitrate}) {
    final urls = _pickAudioUrls(data, bitrate: bitrate);
    return urls.isEmpty ? null : _proxied(urls.first);
  }

  List<String> _pickAudioUrls(Map<String, dynamic> data, {int? bitrate}) {
    final streams = (data['audioStreams'] as List?) ?? const [];
    final candidates = streams.whereType<Map<String, dynamic>>().toList();
    if (candidates.isEmpty) {
      final single = data['audioStreams'] is List ? null : data['audioStream'];
      if (single is String) return [single];
      return const [];
    }

    final target = bitrate ?? _settings.bitrate;
    final scored = <({int score, String url})>[];
    for (final s in candidates) {
      final url = s['url'] as String?;
      if (url == null || url.isEmpty) continue;
      final codec = '${s['codec'] ?? ''}'.toLowerCase();
      final mime = '${s['mimeType'] ?? ''}'.toLowerCase();
      final isOpus = codec.contains('opus') || mime.contains('opus');
      final streamBitrate = _kbps(s);
      var score = streamBitrate;
      if (isOpus && !_settings.preferOpus) score -= 40;
      if (isOpus && _settings.preferOpus) score += 60;
      if (mime.contains('mp4') || codec.contains('mp4a')) score += 20;
      score -= (streamBitrate - target).abs() ~/ 2;
      scored.add((score: score, url: url));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final item in scored.take(3)) item.url];
  }

  List<String> _variants(String url) {
    final health = _health;
    if (health != null && !health.usable) return [url];
    return _proxy.audioVariants(
      url,
      preferWorker: _settings.proxyAudioStreams,
    );
  }

  String _proxied(String url) {
    final health = _health;
    if (health != null && !health.usable) return url;
    final variants = _proxy.audioVariants(
      url,
      preferWorker: _settings.proxyAudioStreams,
    );
    return variants.isEmpty ? url : variants.first;
  }

  int _kbps(Map<String, dynamic> json) {
    final raw = json['bitrate'];
    if (raw is num) {
      return raw > 10000 ? raw ~/ 1000 : raw.toInt();
    }
    final quality = '${json['quality'] ?? ''}';
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match == null ? 128 : int.parse(match.group(1)!);
  }

  int _seconds(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  String? _videoId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }
}
