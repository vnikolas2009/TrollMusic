import '../../../data/models/track.dart';
import '../../network/mirror_manager.dart';
import '../../network/proxy.dart';
import '../../storage/settings.dart';

class InvidiousClient {
  InvidiousClient({required Settings settings, required ProxyConfig proxy})
      : _settings = settings,
        _proxy = proxy {
    _mirrors = MirrorManager(settings: settings, dio: _createDio());
  }

  final Settings _settings;
  final ProxyConfig _proxy;
  late final MirrorManager _mirrors;

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final data = await _json('/api/v1/search', {
      'q': query,
      'type': 'video',
      'sort_by': 'relevance',
    });
    return data
        .whereType<Map<String, dynamic>>()
        .where((e) => '${e['type'] ?? 'video'}'.contains('video'))
        .take(limit)
        .map(_toTrack)
        .toList();
  }

  Future<List<Track>> trending({int limit = 30}) async {
    final data = await _json('/api/v1/trending', {'type': 'music', 'region': 'RU'});
    return data.whereType<Map<String, dynamic>>().take(limit).map(_toTrack).toList();
  }

  Future<Track> video(String videoId) async {
    final data = await _one('/api/v1/videos/$videoId');
    final track = _toTrack(<String, dynamic>{'videoId': videoId, ...data});
    return track.copyWith(streamUrl: _pickAudioUrl(data, videoId));
  }

  Future<String?> audioUrl(String videoId, {int? bitrate}) async {
    final data = await _one('/api/v1/videos/$videoId');
    return _pickAudioUrl(data, videoId, bitrate: bitrate ?? _settings.bitrate);
  }

  Future<List<Map<String, dynamic>>> _json(
    String path,
    Map<String, dynamic> query,
  ) async {
    final response = await _mirrors.get(MirrorKind.invidious, path, query: query);
    final data = response.data;
    return data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];
  }

  Future<Map<String, dynamic>> _one(String path) async {
    final response = await _mirrors.get(MirrorKind.invidious, path);
    final data = response.data;
    return data is Map<String, dynamic> ? data : const {};
  }

  Track _toTrack(Map<String, dynamic> json) {
    final thumbs = (json['videoThumbnails'] as List?) ?? const [];
    final thumb = thumbs.isEmpty
        ? json['thumbnail'] as String?
        : (thumbs.last as Map<String, dynamic>)['url'] as String?;
    final author = json['author'] as String? ??
        json['authorName'] as String? ??
        'Неизвестный исполнитель';
    return Track(
      id: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? 'Без названия',
      artist: author,
      duration: Duration(seconds: (json['lengthSeconds'] as num?)?.toInt() ?? 0),
      thumbnailUrl: thumb,
      source: TrackSource.youtube,
    );
  }

  String? _pickAudioUrl(Map<String, dynamic> data, String videoId, {int? bitrate}) {
    final formats = (data['adaptiveFormats'] as List?) ?? const [];
    final audio = formats
        .whereType<Map<String, dynamic>>()
        .where((f) => '${f['type'] ?? ''}'.startsWith('audio/'))
        .toList();
    if (audio.isEmpty) return null;

    final target = bitrate ?? _settings.bitrate;
    Map<String, dynamic>? best;
    var bestScore = -1 << 30;
    for (final f in audio) {
      final type = '${f['type'] ?? ''}'.toLowerCase();
      final isOpus = type.contains('opus') || type.contains('webm');
      final kbps = _kbps(f);
      var score = kbps - (kbps - target).abs() ~/ 2;
      if (isOpus && _settings.preferOpus) score += 60;
      if (isOpus && !_settings.preferOpus) score -= 40;
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }

    final raw = best?['url'] as String?;
    if (raw == null) return null;
    final absolute = _absolute(raw, videoId);
    return _settings.proxyAudioStreams ? _proxy.passthrough(absolute).toString() : absolute;
  }

  String _absolute(String url, String videoId) {
    if (url.startsWith('http')) return url;
    final origin = _mirrors.instancesOf(MirrorKind.invidious).first;
    return Uri.parse(origin).resolve(url).toString();
  }

  int _kbps(Map<String, dynamic> json) {
    final bitrate = '${json['bitrate'] ?? ''}';
    final match = RegExp(r'(\d+)').firstMatch(bitrate);
    if (match != null) {
      final value = int.parse(match.group(1)!);
      return value > 10000 ? value ~/ 1000 : value;
    }
    return 128;
  }
}
