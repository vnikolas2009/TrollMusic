import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/lyrics_match.dart';
import '../http_client.dart';

/// Источник текстов песен. Возвращает кандидатов, выбирает лучшего сервис.
abstract class LyricsProvider {
  /// Короткий идентификатор: `lrclib`, `kugou`, `qq`, `ovh`.
  String get id;

  /// Название для интерфейса.
  String get label;

  Future<List<LyricsCandidate>> search(LyricsQuery query);
}

dynamic _decode(dynamic data) {
  if (data is String) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  return data;
}

int _seconds(dynamic value) => ((value as num?)?.toDouble() ?? 0).round();

/// LRCLIB: бесплатная база синхронизированных текстов (без ключа).
class LrclibProvider implements LyricsProvider {
  LrclibProvider({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;
  static const _base = 'https://lrclib.net/api';

  @override
  String get id => 'lrclib';

  @override
  String get label => 'LRCLIB';

  @override
  Future<List<LyricsCandidate>> search(LyricsQuery query) async {
    final found = <LyricsCandidate>[];

    if (query.artist.isNotEmpty) {
      final exact = await _get('/get', {
        'track_name': query.title,
        'artist_name': query.artist,
        if (query.album.isNotEmpty) 'album_name': query.album,
        if (query.durationSec > 0) 'duration': '${query.durationSec}',
      });
      if (exact is Map) {
        final c = _candidate(exact);
        if (c != null) found.add(c);
      }
    }

    final list = await _get('/search', {
      'track_name': query.title,
      if (query.artist.isNotEmpty) 'artist_name': query.artist,
    });
    found.addAll(_candidates(list));

    if (found.isEmpty) {
      final loose = await _get('/search', {
        'q': '${query.artist} ${query.title}'.trim(),
      });
      found.addAll(_candidates(loose));
    }
    return found;
  }

  Iterable<LyricsCandidate> _candidates(dynamic list) {
    if (list is! List) return const [];
    return list.whereType<Map>().map(_candidate).whereType<LyricsCandidate>();
  }

  LyricsCandidate? _candidate(Map json) {
    if (json['instrumental'] == true) return null;
    final c = LyricsCandidate(
      title: json['trackName'] as String? ?? '',
      artist: json['artistName'] as String? ?? '',
      album: json['albumName'] as String? ?? '',
      durationSec: _seconds(json['duration']),
      source: id,
      synced: json['syncedLyrics'] as String?,
      plain: json['plainLyrics'] as String?,
    );
    return c.hasAny ? c : null;
  }

  Future<dynamic> _get(String path, Map<String, String> query) async {
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.parse('$_base$path').replace(queryParameters: query),
      );
      if (response.statusCode != 200) return null;
      return _decode(response.data);
    } catch (_) {
      return null;
    }
  }
}

/// Lyrics.ovh: обычный текст без таймкодов, нужен исполнитель и название.
class LyricsOvhProvider implements LyricsProvider {
  LyricsOvhProvider({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  @override
  String get id => 'ovh';

  @override
  String get label => 'Lyrics.ovh';

  @override
  Future<List<LyricsCandidate>> search(LyricsQuery query) async {
    if (query.artist.isEmpty || query.title.isEmpty) return const [];
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.https(
          'api.lyrics.ovh',
          '/v1/${Uri.encodeComponent(query.artist)}/${Uri.encodeComponent(query.title)}',
        ),
      );
      if (response.statusCode != 200) return const [];
      final data = _decode(response.data);
      final text = data is Map ? data['lyrics'] as String? : null;
      final clean = text?.replaceAll('\r\n', '\n').trim();
      if (clean == null || clean.isEmpty) return const [];
      return [
        LyricsCandidate(
          title: query.title,
          artist: query.artist,
          source: id,
          plain: clean,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
