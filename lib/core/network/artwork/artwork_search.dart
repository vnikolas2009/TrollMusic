import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../utils/artwork_match.dart';
import '../http_client.dart';

/// Поиск обложек в открытых каталогах iTunes Search и Deezer (без ключей).
class ArtworkSearch {
  ArtworkSearch({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  /// Скачивает лучшую обложку для трека. Возвращает байты картинки или
  /// `null`, если уверенного совпадения нет.
  Future<Uint8List?> findCover({
    required String title,
    required String artist,
    String album = '',
  }) async {
    final query = [artist, title].where((s) => s.trim().isNotEmpty).join(' ').trim();
    if (query.isEmpty) return null;

    final found = <ArtworkCandidate>[];
    for (final search in [_itunes, _deezer]) {
      try {
        found.addAll(await search(query));
      } catch (e) {
        debugPrint('artwork search: $e');
      }
      final best = pickBestArtwork(found, title: title, artist: artist);
      if (best == null) continue;
      final bytes = await _download(best.url);
      if (bytes != null) return bytes;
    }
    return null;
  }

  Future<List<ArtworkCandidate>> _itunes(String query) async {
    final response = await _dio.get<Object?>(
      'https://itunes.apple.com/search',
      queryParameters: {'term': query, 'media': 'music', 'entity': 'song', 'limit': 8},
    );
    final results = _asMap(response.data)?['results'];
    if (results is! List) return const [];
    return [
      for (final r in results.whereType<Map>())
        if (r['artworkUrl100'] is String)
          ArtworkCandidate(
            title: '${r['trackName'] ?? ''}',
            artist: '${r['artistName'] ?? ''}',
            // в адресе зашит размер; просим крупнее
            url: (r['artworkUrl100'] as String)
                .replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/1000x1000bb.'),
          ),
    ];
  }

  Future<List<ArtworkCandidate>> _deezer(String query) async {
    final response = await _dio.get<Object?>(
      'https://api.deezer.com/search',
      queryParameters: {'q': query, 'limit': 8},
    );
    final data = _asMap(response.data)?['data'];
    if (data is! List) return const [];
    return [
      for (final r in data.whereType<Map>())
        if (r['album'] is Map && (r['album'] as Map)['cover_xl'] is String)
          ArtworkCandidate(
            title: '${r['title'] ?? ''}',
            artist: '${(r['artist'] is Map ? (r['artist'] as Map)['name'] : null) ?? ''}',
            url: (r['album'] as Map)['cover_xl'] as String,
          ),
    ];
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (response.statusCode != 200 || data == null || data.length < 1024) return null;
      return Uint8List.fromList(data);
    } catch (e) {
      debugPrint('artwork download: $e');
      return null;
    }
  }

  /// Ответ может прийти уже разобранным или строкой (iTunes отдаёт JSON с
  /// типом `text/javascript`).
  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}
