import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../utils/lyrics_match.dart';
import '../http_client.dart';
import 'lyrics_providers.dart';

dynamic _json(dynamic data) {
  if (data is String) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  return data;
}

String _unescapeHtml(String s) => s
    .replaceAll('&apos;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// QQ Music: большая база LRC, особенно китайской, корейской, японской и
/// русскоязычной музыки. Отдаёт построчные тексты.
class QqMusicProvider implements LyricsProvider {
  QqMusicProvider({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  @override
  String get id => 'qq';

  @override
  String get label => 'QQ Music';

  static const _headers = <String, String>{'referer': 'https://y.qq.com/'};

  @override
  Future<List<LyricsCandidate>> search(LyricsQuery query) async {
    final keyword = '${query.artist} ${query.title}'.trim();
    if (keyword.isEmpty) return const [];

    final songs = await _songs(keyword);
    final ranked = <MapEntry<double, Map>>[];
    for (final song in songs) {
      final info = _info(song);
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
    for (final entry in ranked.take(2)) {
      final info = _info(entry.value);
      final text = await _lyric(entry.value['songmid'] as String?);
      if (text == null) continue;
      final synced = RegExp(r'\[\d{1,3}:\d{2}').hasMatch(text);
      out.add(LyricsCandidate(
        title: info.title,
        artist: info.artist,
        durationSec: info.durationSec,
        source: id,
        synced: synced ? text : null,
        plain: synced ? null : text,
      ));
    }
    return out;
  }

  ({String title, String artist, int durationSec}) _info(Map song) {
    final singers = song['singer'] as List? ?? const [];
    final names = singers
        .whereType<Map>()
        .map((s) => s['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return (
      title: (song['songname'] ?? song['name']) as String? ?? '',
      artist: names,
      durationSec: (song['interval'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Map>> _songs(String keyword) async {
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {
          'w': keyword,
          'format': 'json',
          'n': '6',
          'p': '1',
        }),
        options: Options(responseType: ResponseType.plain, headers: _headers),
      );
      final data = _json(response.data);
      final list = data is Map && data['data'] is Map
          ? (data['data']['song'] is Map ? data['data']['song']['list'] : null)
          : null;
      return list is List ? list.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _lyric(String? mid) async {
    if (mid == null || mid.isEmpty) return null;
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
          'songmid': mid,
          'format': 'json',
          'nobase64': '0',
        }),
        options: Options(responseType: ResponseType.plain, headers: _headers),
      );
      final data = _json(response.data);
      final raw = data is Map ? data['lyric'] as String? : null;
      if (raw == null || raw.isEmpty) return null;
      final text = _unescapeHtml(utf8.decode(base64.decode(raw))).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
}

/// Kugou: отдаёт KRC (пословные метки). KRC зашифрован простым XOR и сжат
/// zlib; результат переводится в enhanced LRC. Если KRC нет, берётся LRC.
class KugouProvider implements LyricsProvider {
  KugouProvider({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  @override
  String get id => 'kugou';

  @override
  String get label => 'Kugou';

  @override
  Future<List<LyricsCandidate>> search(LyricsQuery query) async {
    final keyword = '${query.artist} ${query.title}'.trim();
    if (keyword.isEmpty) return const [];

    final found = await _candidates(keyword, query.durationSec);
    final ranked = <MapEntry<double, Map>>[];
    for (final item in found) {
      final score = scoreCandidate(
        query,
        LyricsCandidate(
          title: item['song'] as String? ?? '',
          artist: item['singer'] as String? ?? '',
          durationSec: (((item['duration'] as num?) ?? 0) / 1000).round(),
          source: id,
          plain: 'x',
        ),
      );
      if (score != null) ranked.add(MapEntry(score, item));
    }
    ranked.sort((a, b) => b.key.compareTo(a.key));

    final out = <LyricsCandidate>[];
    for (final entry in ranked.take(2)) {
      final item = entry.value;
      final text = await _download(item);
      if (text == null) continue;
      final synced = RegExp(r'\[\d{1,3}:\d{2}').hasMatch(text);
      out.add(LyricsCandidate(
        title: item['song'] as String? ?? '',
        artist: item['singer'] as String? ?? '',
        durationSec: (((item['duration'] as num?) ?? 0) / 1000).round(),
        source: id,
        synced: synced ? text : null,
        plain: synced ? null : text,
      ));
    }
    return out;
  }

  Future<List<Map>> _candidates(String keyword, int durationSec) async {
    try {
      final response = await _dio.getUri<dynamic>(
        Uri.https('lyrics.kugou.com', '/search', {
          'ver': '1',
          'man': 'yes',
          'client': 'pc',
          'keyword': keyword,
          'duration': durationSec > 0 ? '${durationSec * 1000}' : '',
          'hash': '',
        }),
        options: Options(responseType: ResponseType.plain),
      );
      final data = _json(response.data);
      final list = data is Map ? data['candidates'] : null;
      return list is List ? list.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _download(Map item) async {
    final id = item['id'];
    final key = item['accesskey'];
    if (id == null || key == null) return null;

    // Сначала KRC (пословные метки), затем обычный LRC.
    for (final fmt in const ['krc', 'lrc']) {
      try {
        final response = await _dio.getUri<dynamic>(
          Uri.https('lyrics.kugou.com', '/download', {
            'ver': '1',
            'client': 'pc',
            'id': '$id',
            'accesskey': '$key',
            'fmt': fmt,
            'charset': 'utf8',
          }),
          options: Options(responseType: ResponseType.plain),
        );
        final data = _json(response.data);
        final content = data is Map ? data['content'] as String? : null;
        if (content == null || content.isEmpty) continue;

        final bytes = base64.decode(content);
        final text = fmt == 'krc'
            ? krcToEnhancedLrc(bytes)
            : utf8.decode(bytes, allowMalformed: true).replaceAll('﻿', '');
        if (text != null && text.trim().isNotEmpty) return text.trim();
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

const _krcKey = <int>[
  64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105,
];

/// Расшифровывает KRC Kugou: пропустить 4 байта заголовка, XOR с ключом,
/// распаковать zlib.
String? decodeKrc(List<int> bytes) {
  if (bytes.length <= 4) return null;
  final body = Uint8List(bytes.length - 4);
  for (var i = 0; i < body.length; i++) {
    body[i] = bytes[i + 4] ^ _krcKey[i % _krcKey.length];
  }
  try {
    return utf8.decode(zlib.decode(body), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Переводит KRC (`[старт,длит]<смещение,длит,0>слово`) в enhanced LRC.
/// Смещения слов в KRC считаются от начала строки. Возвращает `null`,
/// если в тексте нет строк с пословными метками.
String? krcToEnhancedLrc(List<int> bytes) {
  final text = decodeKrc(bytes);
  return text == null ? null : krcTextToEnhancedLrc(text);
}

String? krcTextToEnhancedLrc(String krc) {
  final lineRe = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final wordRe = RegExp(r'<(\d+),(\d+),\d+>');
  final out = <String>[];

  for (final raw in krc.replaceAll('\r', '').split('\n')) {
    final m = lineRe.firstMatch(raw.trim());
    if (m == null) continue;
    final lineStart = int.parse(m.group(1)!);
    final body = m.group(3)!;
    final tags = wordRe.allMatches(body).toList();
    if (tags.isEmpty) continue;

    final b = StringBuffer(_stamp(lineStart, '[', ']'));
    for (var i = 0; i < tags.length; i++) {
      final end = i + 1 < tags.length ? tags[i + 1].start : body.length;
      final word = body.substring(tags[i].end, end);
      if (word.trim().isEmpty) continue;
      final start = lineStart + int.parse(tags[i].group(1)!);
      b.write(_stamp(start, '<', '>'));
      b.write(word);
    }
    final line = b.toString().trimRight();
    if (line.contains('<')) out.add(line);
  }
  return out.isEmpty ? null : out.join('\n');
}

String _stamp(int ms, String open, String close) {
  final m = (ms ~/ 60000).toString().padLeft(2, '0');
  final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
  final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$open$m:$s.$cs$close';
}
