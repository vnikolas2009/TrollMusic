import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/lyrics_match.dart';
import '../http_client.dart';

/// Источник текстов песен. Возвращает кандидатов, выбирает лучшего сервис.
abstract class LyricsProvider {
  /// Короткий идентификатор: `lrclib`, `netease`, `ovh`.
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

/// NetEase Cloud Music: большая база LRC, в том числе русскоязычных и азиатских
/// песен. Для части треков отдаёт пословные метки — тогда текст приходит
/// в виде enhanced LRC.
class NeteaseProvider implements LyricsProvider {
  NeteaseProvider({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  @override
  String get id => 'netease';

  @override
  String get label => 'NetEase';

  static const _headers = <String, String>{
    'referer': 'https://music.163.com/',
    'cookie': 'appver=2.0.2; os=pc',
  };

  @override
  Future<List<LyricsCandidate>> search(LyricsQuery query) async {
    final keyword = '${query.artist} ${query.title}'.trim();
    final songs = await _songs(keyword);

    // Берём только подходящие по названию и исполнителю, чтобы не тратить запросы.
    final ranked = <MapEntry<double, Map>>[];
    for (final song in songs) {
      final info = _songInfo(song);
      final score = scoreCandidate(
        query,
        LyricsCandidate(
          title: info.title,
          artist: info.artist,
          durationSec: info.durationSec,
          source: id,
          plain: 'x',
        ),
      );
      if (score != null) ranked.add(MapEntry(score, song));
    }
    ranked.sort((a, b) => b.key.compareTo(a.key));

    final out = <LyricsCandidate>[];
    for (final entry in ranked.take(3)) {
      final song = entry.value;
      final info = _songInfo(song);
      final lyric = await _lyric(song['id']);
      if (lyric == null) continue;
      out.add(LyricsCandidate(
        title: info.title,
        artist: info.artist,
        album: info.album,
        durationSec: info.durationSec,
        source: id,
        synced: lyric.synced ? lyric.text : null,
        plain: lyric.synced ? null : lyric.text,
      ));
    }
    return out;
  }

  ({String title, String artist, String album, int durationSec}) _songInfo(Map song) {
    final artists = (song['artists'] ?? song['ar']) as List? ?? const [];
    final names = artists
        .whereType<Map>()
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    final album = song['album'] ?? song['al'];
    final ms = ((song['duration'] ?? song['dt']) as num?)?.toInt() ?? 0;
    return (
      title: song['name'] as String? ?? '',
      artist: names,
      album: album is Map ? album['name'] as String? ?? '' : '',
      durationSec: (ms / 1000).round(),
    );
  }

  Future<List<Map>> _songs(String keyword) async {
    if (keyword.isEmpty) return const [];
    try {
      final response = await _dio.postUri<dynamic>(
        Uri.parse('https://music.163.com/api/search/get'),
        data: {'s': keyword, 'type': '1', 'limit': '8', 'offset': '0'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: _headers,
        ),
      );
      final data = _decode(response.data);
      final result = data is Map ? data['result'] : null;
      final songs = result is Map ? result['songs'] : null;
      return songs is List ? songs.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<({String text, bool synced})?> _lyric(dynamic songId) async {
    if (songId == null) return null;
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.https('music.163.com', '/api/song/lyric', {
          'id': '$songId',
          'lv': '1',
          'kv': '1',
          'tv': '-1',
          'yv': '1',
        }),
        options: Options(responseType: ResponseType.plain, headers: _headers),
      );
      final data = _decode(response.data);
      if (data is! Map) return null;

      final yrcBlock = data['yrc'];
      final yrc = yrcBlock is Map ? yrcBlock['lyric'] as String? : null;
      if (yrc != null && yrc.trim().isNotEmpty) {
        final enhanced = neteaseYrcToEnhancedLrc(yrc);
        if (enhanced != null) return (text: enhanced, synced: true);
      }

      final lrcBlock = data['lrc'];
      final lrc = lrcBlock is Map ? lrcBlock['lyric'] as String? : null;
      if (lrc == null || lrc.trim().isEmpty) return null;
      final hasStamps = RegExp(r'\[\d{1,3}:\d{2}').hasMatch(lrc);
      return (text: lrc, synced: hasStamps);
    } catch (_) {
      return null;
    }
  }
}

/// Переводит формат NetEase `[старт,длит](старт,длит,0)слово...` в enhanced LRC.
/// Возвращает `null`, если в тексте нет ни одной строки в этом формате.
String? neteaseYrcToEnhancedLrc(String yrc) {
  final lineRe = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final wordRe = RegExp(r'\((\d+),(\d+),\d+\)');
  final out = <String>[];

  for (final raw in yrc.replaceAll('\r', '').split('\n')) {
    final m = lineRe.firstMatch(raw.trim());
    if (m == null) continue;
    final body = m.group(3)!;
    final tags = wordRe.allMatches(body).toList();
    if (tags.isEmpty) continue;

    final b = StringBuffer(_lrcStamp(int.parse(m.group(1)!), '[', ']'));
    for (var i = 0; i < tags.length; i++) {
      final end = i + 1 < tags.length ? tags[i + 1].start : body.length;
      final text = body.substring(tags[i].end, end);
      if (text.trim().isEmpty) continue;
      b.write(_lrcStamp(int.parse(tags[i].group(1)!), '<', '>'));
      b.write(text);
    }
    final line = b.toString().trimRight();
    if (line.contains('<')) out.add(line);
  }
  return out.isEmpty ? null : out.join('\n');
}

String _lrcStamp(int ms, String open, String close) {
  final m = (ms ~/ 60000).toString().padLeft(2, '0');
  final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
  final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$open$m:$s.$cs$close';
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
