import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../../utils/async_utils.dart';
import '../../utils/audio_pick.dart';
import '../http_client.dart';
import 'stream_candidate.dart';

/// Прямой клиент публичного InnerTube API YouTube / YouTube Music.
///
/// Ключи и OAuth не нужны. Для потоков используются клиенты, которым YouTube
/// (на момент написания) не требует PO-токен: `ANDROID_VR` и `ANDROID` без
/// `androidSdkVersion`. Клиенты ANDROID/IOS/WEB с PO-токеном отдают ссылки,
/// которые отвечают 403, поэтому здесь они намеренно не используются.
class InnerTubeClient {
  InnerTubeClient({required Settings settings})
      : _dio = createDio(
          settings: settings,
          receiveTimeout: const Duration(seconds: 12),
        );

  final Dio _dio;

  static const _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _base = 'https://www.youtube.com/youtubei/v1';
  static const _musicBase = 'https://music.youtube.com/youtubei/v1';

  /// Фильтр «Песни» в поиске YouTube Music.
  static const _songsParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  static const _streamClients = <_ClientProfile>[
    _ClientProfile(
      name: 'ANDROID_VR',
      version: AppConfig.androidVrVersion,
      clientId: 28,
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/${AppConfig.androidVrVersion} '
          '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      extra: {
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'osName': 'Android',
        'osVersion': '12L',
        'buildId': 'SQ3A.220605.009.A1',
      },
    ),
    _ClientProfile(
      name: 'ANDROID',
      version: AppConfig.androidSdklessVersion,
      clientId: 3,
      userAgent:
          'com.google.android.youtube/${AppConfig.androidSdklessVersion} (Linux; U; Android 11) gzip',
      extra: {'osName': 'Android', 'osVersion': '11'},
    ),
  ];

  static const _webClient = _ClientProfile(
    name: 'WEB',
    version: '2.20250310.01.00',
    clientId: 1,
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  );

  /// Поиск по YouTube Music (только песни): название, исполнитель, альбом, длительность.
  Future<List<Track>> searchMusic(String query, {int limit = 30}) async {
    final response = await _dio.postUri<dynamic>(
      Uri.parse('$_musicBase/search?prettyPrint=false'),
      data: {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': AppConfig.ytMusicClientVersion,
            'hl': 'ru',
            'gl': 'RU',
          },
        },
        'query': query,
        'params': _songsParams,
      },
      options: Options(
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        headers: {
          'user-agent': _webClient.userAgent,
          'origin': 'https://music.youtube.com',
          'referer': 'https://music.youtube.com/',
          'x-origin': 'https://music.youtube.com',
        },
      ),
    );
    final data = response.data;
    if (data is! Map) return const [];
    return _parseMusicItems(data, limit: limit);
  }

  /// Обычный поиск (видео) — запасной вариант, если YouTube Music недоступен.
  Future<List<Track>> search(String query, {int limit = 30}) async {
    final response = await _post(
      'search',
      {
        'query': query,
        'params': 'EgIQAQ%3D%3D',
        'context': _context(_webClient),
      },
      _webClient,
    );
    return _parseSearch(response, limit: limit);
  }

  /// Прямые ссылки на аудио, отсортированные под выбранное качество.
  /// Клиенты опрашиваются параллельно, побеждает первый, кто ответил.
  Future<List<StreamCandidate>> audioStreams(
    String videoId, {
    required AudioQuality quality,
    required bool onWifi,
    bool aacOnly = false,
  }) {
    return firstNonEmptyList<StreamCandidate>(
      [
        for (final client in _streamClients)
          () => _streamsFrom(
                client,
                videoId,
                quality: quality,
                onWifi: onWifi,
                aacOnly: aacOnly,
              ),
      ],
      timeout: const Duration(seconds: 12),
    );
  }

  Future<List<StreamCandidate>> _streamsFrom(
    _ClientProfile client,
    String videoId, {
    required AudioQuality quality,
    required bool onWifi,
    required bool aacOnly,
  }) async {
    final data = await _post(
      'player',
      {
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
        'context': _context(client),
      },
      client,
    );

    final playability = data['playabilityStatus'];
    if (playability is Map) {
      final status = playability['status'];
      if (status != null && status != 'OK') return const [];
    }

    final streaming = data['streamingData'];
    if (streaming is! Map) return const [];

    double? loudness;
    final config = data['playerConfig'];
    if (config is Map) {
      final audio = config['audioConfig'];
      if (audio is Map && audio['loudnessDb'] is num) {
        loudness = (audio['loudnessDb'] as num).toDouble();
      }
    }

    final formats = <AudioFormat>[];
    final raw = streaming['adaptiveFormats'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final mime = '${item['mimeType'] ?? ''}';
        if (!mime.toLowerCase().startsWith('audio/')) continue;
        final url = item['url'];
        if (url is! String || url.isEmpty) continue;
        final bps = (item['averageBitrate'] as num?) ??
            (item['bitrate'] as num?) ??
            128000;
        final kbps = bps > 10000 ? bps ~/ 1000 : bps.toInt();
        formats.add(
          AudioFormat(
            url: url,
            mime: mime,
            kbps: kbps,
            loudnessDb: loudness,
          ),
        );
      }
    }

    final ranked = rankFormats(
      formats,
      quality: quality,
      onWifi: onWifi,
      aacOnly: aacOnly,
    );
    return [
      for (final f in ranked)
        StreamCandidate(
          url: f.url,
          userAgent: client.userAgent,
          mime: f.mime,
          kbps: f.kbps,
          loudnessDb: f.loudnessDb,
        ),
    ];
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
    _ClientProfile client,
  ) async {
    final response = await _dio.postUri<dynamic>(
      Uri.parse('$_base/$endpoint?key=$_apiKey&prettyPrint=false'),
      data: body,
      options: Options(
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        headers: {
          'user-agent': client.userAgent,
          'x-youtube-client-name': '${client.clientId}',
          'x-youtube-client-version': client.version,
          'origin': 'https://www.youtube.com',
          'referer': 'https://www.youtube.com/',
        },
      ),
    );
    final data = response.data;
    return data is Map<String, dynamic> ? data : const {};
  }

  Map<String, dynamic> _context(_ClientProfile client) => {
        'client': {
          'clientName': client.name,
          'clientVersion': client.version,
          'hl': 'ru',
          'gl': 'RU',
          ...client.extra,
        },
      };

  // ---------------------------------------------------------------- парсинг

  static const _typeLabels = {
    'song',
    'video',
    'single',
    'episode',
    'песня',
    'видео',
    'сингл',
    'эпизод',
  };

  List<Track> _parseMusicItems(Map<dynamic, dynamic> data, {required int limit}) {
    final tracks = <Track>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (tracks.length >= limit) return;
      if (node is Map) {
        final item = node['musicResponsiveListItemRenderer'];
        if (item is Map) {
          final track = _musicItemToTrack(item);
          if (track != null && seen.add(track.id)) tracks.add(track);
          return;
        }
        for (final value in node.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      }
    }

    walk(data);
    return tracks;
  }

  Track? _musicItemToTrack(Map<dynamic, dynamic> item) {
    final videoId = _findString(item, 'videoId');
    if (videoId == null || videoId.length != 11) return null;

    final columns = item['flexColumns'];
    if (columns is! List || columns.isEmpty) return null;

    List<dynamic> runsOf(int index) {
      if (index >= columns.length) return const [];
      final column = columns[index];
      if (column is! Map) return const [];
      final renderer = column['musicResponsiveListItemFlexColumnRenderer'];
      if (renderer is! Map) return const [];
      final text = renderer['text'];
      if (text is! Map) return const [];
      final runs = text['runs'];
      return runs is List ? runs : const [];
    }

    String textOf(dynamic run) => run is Map ? '${run['text'] ?? ''}' : '';

    final titleRuns = runsOf(0);
    if (titleRuns.isEmpty) return null;
    final title = titleRuns.map(textOf).join().trim();
    if (title.isEmpty) return null;

    // Подзаголовок: «Исполнитель • Альбом • 3:45» (части разделены « • »).
    final groups = <List<String>>[<String>[]];
    for (final run in runsOf(1)) {
      final text = textOf(run);
      if (text.trim() == '•') {
        groups.add(<String>[]);
      } else {
        groups.last.add(text);
      }
    }
    final parts = [
      for (final g in groups)
        if (g.join().trim().isNotEmpty) g.join().trim(),
    ];
    if (parts.length > 1 && _typeLabels.contains(parts.first.toLowerCase())) {
      parts.removeAt(0);
    }

    var duration = Duration.zero;
    if (parts.isNotEmpty && _isDuration(parts.last)) {
      duration = _parseDuration(parts.removeLast());
    }
    final artist = parts.isNotEmpty ? parts.first : 'YouTube Music';
    final album = parts.length > 1 ? parts[1] : '';

    String? thumb;
    final thumbs = _findList(item['thumbnail'], 'thumbnails');
    if (thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map && last['url'] is String) {
        thumb = (last['url'] as String).replaceAll(
          RegExp(r'=w\d+-h\d+[^&]*$'),
          '=w512-h512-l90-rj',
        );
      }
    }

    return Track(
      id: videoId,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      thumbnailUrl: thumb,
      explicit: jsonEncode(item).contains('MUSIC_EXPLICIT_BADGE'),
      source: TrackSource.youtube,
    );
  }

  String? _findString(dynamic node, String key) {
    if (node is Map) {
      final direct = node[key];
      if (direct is String && direct.isNotEmpty) return direct;
      for (final value in node.values) {
        final found = _findString(value, key);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findString(value, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<dynamic> _findList(dynamic node, String key) {
    if (node is Map) {
      final direct = node[key];
      if (direct is List) return direct;
      for (final value in node.values) {
        final found = _findList(value, key);
        if (found.isNotEmpty) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findList(value, key);
        if (found.isNotEmpty) return found;
      }
    }
    return const [];
  }

  bool _isDuration(String text) => RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(text);

  List<Track> _parseSearch(Map<String, dynamic> data, {required int limit}) {
    final tracks = <Track>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (tracks.length >= limit) return;
      if (node is Map) {
        final renderer = node['videoRenderer'];
        if (renderer is Map<String, dynamic>) {
          final track = _videoToTrack(renderer);
          if (track != null && seen.add(track.id)) tracks.add(track);
        }
        for (final value in node.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      }
    }

    walk(data);
    return tracks;
  }

  Track? _videoToTrack(Map<String, dynamic> json) {
    final id = json['videoId'] as String?;
    if (id == null || id.isEmpty) return null;
    final title = _runsText(json['title']) ?? 'Без названия';
    final artist = _runsText(json['ownerText']) ??
        _runsText(json['longBylineText']) ??
        _runsText(json['shortBylineText']) ??
        'YouTube';
    final duration = _parseDuration(
      _simpleText(json['lengthText']) ??
          _simpleText(_access(json['lengthText'], ['simpleText'])),
    );
    final thumbs = _access(json['thumbnail'], ['thumbnails']);
    String? thumb;
    if (thumbs is List && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map) thumb = last['url'] as String?;
    }
    return Track(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
      thumbnailUrl: thumb,
      source: TrackSource.youtube,
    );
  }

  String? _runsText(dynamic node) {
    if (node is Map) {
      final runs = node['runs'];
      if (runs is List && runs.isNotEmpty) {
        return runs
            .whereType<Map>()
            .map((r) => '${r['text'] ?? ''}')
            .join()
            .trim();
      }
      final simple = node['simpleText'];
      if (simple is String) return simple;
    }
    if (node is String) return node;
    return null;
  }

  String? _simpleText(dynamic node) {
    if (node is String) return node;
    if (node is Map && node['simpleText'] is String) {
      return node['simpleText'] as String;
    }
    return null;
  }

  dynamic _access(dynamic node, List<String> path) {
    dynamic current = node;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  Duration _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return Duration.zero;
    final parts = raw.split(':').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    if (parts.isEmpty) return Duration.zero;
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part;
    }
    return Duration(seconds: seconds);
  }
}

class _ClientProfile {
  const _ClientProfile({
    required this.name,
    required this.version,
    required this.clientId,
    required this.userAgent,
    this.extra = const {},
  });

  final String name;
  final String version;
  final int clientId;
  final String userAgent;
  final Map<String, dynamic> extra;
}
