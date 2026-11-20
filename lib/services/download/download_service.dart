import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/network/piped/youtube_music_client.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../storage/storage_service.dart';

enum DownloadState { queued, running, done, failed, canceled }

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.state,
  });

  final int received;
  final int total;
  final DownloadState state;

  double get fraction {
    if (total <= 0) {
      return state == DownloadState.done ? 1 : 0;
    }
    return (received / total).clamp(0.0, 1.0);
  }
}

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

  static const maxConcurrent = 2;

  final _jobs = <String, DownloadProgress>{};
  final _tokens = <String, CancelToken>{};
  bool _batchCanceled = false;

  final _revision = ValueNotifier<int>(0);

  ValueListenable<int> get revision => _revision;

  DownloadProgress? progressOf(String trackId) => _jobs[trackId];
  bool isDownloading(String trackId) => _jobs.containsKey(trackId);
  int get activeCount => _jobs.length;

  void _bump() => _revision.value++;

  void _set(String trackId, DownloadProgress progress) {
    _jobs[trackId] = progress;
    _bump();
  }

  Future<Track> download(Track track, {bool withLyrics = true}) async {
    if (_jobs.containsKey(track.id)) return track;

    final token = CancelToken();
    _tokens[track.id] = token;

    _set(track.id, const DownloadProgress(
      received: 0,
      total: 0,
      state: DownloadState.queued,
    ));

    try {
      final url = track.streamUrl ?? await _youtube.streamUrlForTrack(track);
      if (url == null || url.isEmpty) {
        throw StateError('Не удалось получить ссылку на аудио');
      }

      final extension = _extensionOf(url);
      final target = File(p.join(_storage.audioDir.path, '${track.id}.$extension'));
      await _downloadFile(url, target, track.id, token);

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
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const DownloadCanceled();
      }
      rethrow;
    } finally {
      _tokens.remove(track.id);
      _jobs.remove(track.id);
      _bump();
    }
  }

  Future<List<Track>> downloadAll(
    Iterable<Track> tracks, {
    void Function(int done, int total)? onProgress,
  }) async {
    final list = tracks.toList();
    final done = <Track>[];
    var cursor = 0;
    var finished = 0;
    _batchCanceled = false;

    Future<void> worker() async {
      while (cursor < list.length && !_batchCanceled) {
        final track = list[cursor++];
        try {
          done.add(await download(track));
        } catch (_) {
          if (_batchCanceled) return;
        } finally {
          finished++;
          onProgress?.call(finished, list.length);
        }
      }
    }

    final workers = list.length < maxConcurrent ? list.length : maxConcurrent;
    await Future.wait(List.generate(workers, (_) => worker()));
    return done;
  }

  void cancel(String trackId) {
    final token = _tokens[trackId];
    if (token == null) return;
    if (!token.isCancelled) token.cancel('cancelled');
  }

  void cancelAll() {
    _batchCanceled = true;
    for (final id in _tokens.keys.toList()) {
      cancel(id);
    }
  }

  Future<void> deleteDownload(String trackId) async {
    final track = _library.trackById(trackId);
    if (track == null) return;
    await _removeFile(track.localPath);
    await _removeFile(track.artworkPath);
    await _removeFile(track.lyricsPath);
    await _library.saveTrack(
      track.copyWith(localPath: '', artworkPath: '', lyricsPath: ''),
    );
    _jobs.remove(trackId);
    _bump();
  }

  Future<void> deleteMany(Iterable<String> trackIds) async {
    for (final id in trackIds) {
      await deleteDownload(id);
    }
  }

  Future<int> downloadedBytes() async {
    var total = 0;
    for (final track in _library.downloaded) {
      final path = track.localPath;
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  Future<void> _removeFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _downloadFile(
    String url,
    File target,
    String trackId,
    CancelToken token,
  ) async {
    await _dio.download(
      url,
      target.path,
      deleteOnError: true,
      cancelToken: token,
      onReceiveProgress: (received, total) {
        _set(
          trackId,
          DownloadProgress(
            received: received,
            total: total > 0 ? total : 0,
            state: DownloadState.running,
          ),
        );
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

class DownloadCanceled implements Exception {
  const DownloadCanceled();

  @override
  String toString() => 'Загрузка отменена';
}
