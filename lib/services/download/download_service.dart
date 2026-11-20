import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/network/piped/youtube_music_client.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../storage/storage_service.dart';

class DownloadService {
  DownloadService({
    required LibraryRepository library,
    required StorageService storage,
    required YouTubeMusicClient youtube,
  })  : _library = library,
        _storage = storage,
        _youtube = youtube,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(days: 2),
          followRedirects: true,
        ));

  final LibraryRepository _library;
  final StorageService _storage;
  final YouTubeMusicClient _youtube;
  final Dio _dio;

  final _progress = <String, double>{};
  final _active = <String>{};

  double? progressOf(String trackId) => _progress[trackId];
  bool isDownloading(String trackId) => _active.contains(trackId);

  Future<Track> download(Track track, {bool withLyrics = true}) async {
    if (_active.contains(track.id)) return track;
    _active.add(track.id);
    _progress[track.id] = 0;

    try {
      final url = track.streamUrl ?? await _youtube.streamUrl(track.id);
      if (url == null || url.isEmpty) {
        throw StateError('Не удалось получить ссылку на аудио');
      }

      final extension = _extensionOf(url);
      final target = File(p.join(_storage.audioDir.path, '${track.id}.$extension'));
      await _downloadFile(url, target, track.id);

      String? artworkPath;
      if (track.artworkPath == null && (track.thumbnailUrl?.isNotEmpty ?? false)) {
        artworkPath = await _downloadArtwork(track);
      }

      String? lyricsPath;
      if (withLyrics) {
        lyricsPath = await _downloadLyrics(track);
      }

      final saved = track.copyWith(
        localPath: target.path,
        artworkPath: artworkPath,
        lyricsPath: lyricsPath,
        streamUrl: url,
      );
      await _library.saveTrack(saved);
      return saved;
    } finally {
      _progress.remove(track.id);
      _active.remove(track.id);
    }
  }

  Future<List<Track>> downloadAll(
    Iterable<Track> tracks, {
    void Function(int done, int total)? onProgress,
  }) async {
    final list = tracks.toList();
    final result = <Track>[];
    for (var i = 0; i < list.length; i++) {
      result.add(await download(list[i]));
      onProgress?.call(i + 1, list.length);
    }
    return result;
  }

  Future<void> deleteDownload(String trackId) async {
    final track = _library.trackById(trackId);
    if (track == null) return;
    final files = [track.localPath, track.artworkPath, track.lyricsPath];
    for (final path in files) {
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _library.saveTrack(
      track.copyWith(localPath: '', artworkPath: '', lyricsPath: ''),
    );
  }

  Future<void> _downloadFile(String url, File target, String trackId) async {
    await _dio.download(
      url,
      target.path,
      deleteOnError: true,
      cancelToken: CancelToken(),
      onReceiveProgress: (received, total) {
        if (total > 0) _progress[trackId] = received / total;
      },
    );
  }

  Future<String?> _downloadArtwork(Track track) async {
    final url = track.thumbnailUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final path = p.join(_storage.artworkDir.path, '${track.id}.jpg');
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _downloadLyrics(Track track) async {
    try {
      final existing = _library.lyricsFor(track.id);
      if (existing != null && existing.trim().isNotEmpty) {
        final path = track.lyricsPath;
        if (path != null && await File(path).exists()) return path;
        final fallback = p.join(_storage.lyricsDir.path, '${track.id}.lrc');
        await File(fallback).writeAsString(existing, flush: true);
        return fallback;
      }

      final lyrics = await _storage.fetchLyricsFromLrclib(track);
      if (lyrics == null || lyrics.isEmpty) return null;
      final lrc = lyrics.synced
          ? LrcParser.toLrc(lyrics, title: track.title, artist: track.artist)
          : lyrics.plainText;
      final path = p.join(_storage.lyricsDir.path, '${track.id}.lrc');
      await File(path).writeAsString(lrc, flush: true);
      await _library.saveLyrics(track.id, lrc);
      return path;
    } catch (_) {
      return null;
    }
  }

  String _extensionOf(String url) {
    final uri = Uri.tryParse(url);
    final mime = uri?.queryParameters['mime'] ?? uri?.queryParameters['mimeType'];
    if (mime != null) {
      if (mime.contains('webm') || mime.contains('opus')) return 'opus';
      if (mime.contains('mp4') || mime.contains('m4a')) return 'm4a';
    }
    final segment = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    final ext = p.extension(segment).replaceFirst('.', '').toLowerCase();
    if (['m4a', 'mp4', 'opus', 'webm', 'mp3'].contains(ext)) {
      return ext == 'webm' ? 'opus' : ext;
    }
    return 'm4a';
  }
}
