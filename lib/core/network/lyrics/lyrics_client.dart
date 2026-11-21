import 'package:dio/dio.dart';

import '../../../data/models/lyrics.dart';
import '../../network/http_client.dart';
import '../../utils/lrc_parser.dart';

class LyricsClient {
  LyricsClient({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;
  static const _base = 'https://lrclib.net/api';

  Future<Lyrics?> get({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final query = <String, String>{
      'track_name': _clean(title),
      'artist_name': _clean(artist),
      if (album != null && album.isNotEmpty) 'album_name': _clean(album),
      if (duration != null && duration.inSeconds > 0)
        'duration': '${duration.inSeconds}',
    };
    final json = await _request('/get', query);
    if (json == null) return null;
    return _toLyrics(json);
  }

  Future<List<Lyrics>> search({
    required String title,
    String? artist,
  }) async {
    final query = <String, String>{
      'track_name': _clean(title),
      if (artist != null && artist.isNotEmpty) 'artist_name': _clean(artist),
    };
    final data = await _raw('/search', query);
    final list = data is List ? data : (data is Map ? data['data'] : null);
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(_toLyrics)
        .where((l) => !l.isEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchRaw({
    required String query,
    int limit = 20,
  }) async {
    final data = await _raw('/search', {'q': _clean(query)});
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map((e) => <String, dynamic>{
              'id': e['id'],
              'title': e['trackName'],
              'artist': e['artistName'],
              'album': e['albumName'],
              'durationMs': ((e['duration'] as num?)?.toDouble() ?? 0) * 1000 ~/ 1,
              'synced': e['syncedLyrics'] != null,
            })
        .toList();
  }

  Future<Lyrics?> byId(int id) async {
    final json = await _request('/get/$id', const {});
    return json == null ? null : _toLyrics(json);
  }

  Future<Map<String, dynamic>?> _request(
    String path,
    Map<String, String> query,
  ) async {
    final data = await _raw(path, query);
    return data is Map<String, dynamic> ? data : null;
  }

  Future<dynamic> _raw(String path, Map<String, String> query) async {
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.parse('$_base$path').replace(queryParameters: query),
        options: Options(
          headers: {
            'accept': 'application/json',
            'user-agent': 'TrollMusic/1.0 (+https://github.com/vnikolas2009/TrollMusic)',
          },
        ),
      );
      if (response.statusCode == 404) return null;
      return response.data;
    } on DioException {
      return null;
    }
  }

  Lyrics _toLyrics(Map<String, dynamic> json) {
    final synced = json['syncedLyrics'] as String? ?? '';
    final plain = json['plainLyrics'] as String? ?? '';
    if (synced.trim().isNotEmpty) {
      final parsed = LrcParser.parse(synced);
      return Lyrics(
        lines: parsed.lines,
        plainText: parsed.plainText.isEmpty ? plain : parsed.plainText,
        synced: parsed.synced,
        title: json['trackName'] as String?,
        artist: json['artistName'] as String?,
      );
    }
    return Lyrics(
      plainText: plain,
      lines: plain
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => LyricLine(time: Duration.zero, text: l.trim()))
          .toList(),
      synced: false,
      title: json['trackName'] as String?,
      artist: json['artistName'] as String?,
    );
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}
