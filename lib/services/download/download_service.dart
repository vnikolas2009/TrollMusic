import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/network/http_client.dart';
import '../../core/storage/settings.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../audio/audio_resolver_service.dart';
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

/// Общий прогресс пакетного скачивания.
class DownloadBatchProgress {
  const DownloadBatchProgress({
    required this.total,
    required this.completed,
    required this.succeeded,
    required this.failed,
    required this.currentTitles,
    this.canceled = false,
  });

  final int total;
  final int completed;
  final int succeeded;
  final int failed;
  final List<String> currentTitles;
  final bool canceled;

  int get remaining => (total - completed).clamp(0, total);

  double get fraction {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();

  bool get isRunning => !canceled && completed < total;

  bool get isFinished => !isRunning;
}

class DownloadService {
  DownloadService({
    required LibraryRepository library,
    required StorageService storage,
    required AudioResolverService resolver,
    required Settings settings,
  })  : _library = library,
        _storage = storage,
        _resolver = resolver,
        _dio = createDio(
          settings: settings,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(days: 2),
        )..options.followRedirects = true;

  final LibraryRepository _library;
  final StorageService _storage;
  final AudioResolverService _resolver;
  final Dio _dio;

  static const maxConcurrent = 2;

  final _jobs = <String, DownloadProgress>{};
  final _tokens = <String, CancelToken>{};

  bool _batchCanceled = false;
  bool _batchRunning = false;

  final _revision = ValueNotifier<int>(0);
  final _batchProgress = ValueNotifier<DownloadBatchProgress?>(null);

  ValueListenable<int> get revision => _revision;

  /// Слушатель общего прогресса пакетного скачивания.
  ValueListenable<DownloadBatchProgress?> get batchProgress =>
      _batchProgress;

  DownloadProgress? progressOf(String trackId) => _jobs[trackId];

  bool isDownloading(String trackId) => _jobs.containsKey(trackId);

  int get activeCount => _jobs.length;

  void dismissBatchProgress() {
    _batchProgress.value = null;
  }

  void _bump() => _revision.value++;

  void _set(String trackId, DownloadProgress progress) {
    _jobs[trackId] = progress;
    _bump();
  }

  Future<Track> download(Track track, {bool withLyrics = true}) async {
    if (_jobs.containsKey(track.id)) return track;

    final token = CancelToken();
    _tokens[track.id] = token;

    _set(
      track.id,
      const DownloadProgress(
        received: 0,
        total: 0,
        state: DownloadState.queued,
      ),
    );

    try {
      final known = (track.streamUrl ?? '').trim();
      final attempted = <String>{};
      Object? lastError;

      Future<(File file, String url)?> attempt(
        Iterable<String> candidates,
      ) async {
        for (final candidate in candidates) {
          if (candidate.isEmpty ||
              candidate.contains('.m3u8') ||
              !attempted.add(candidate)) {
            continue;
          }

          try {
            final extension = _extensionOf(candidate);
            final file = File(
              p.join(_storage.audioDir.path, '${track.id}.$extension'),
            );

            await _downloadFile(candidate, file, track.id, token);
            return (file, candidate);
          } catch (error) {
            if (error is DioException && CancelToken.isCancel(error)) {
              rethrow;
            }
            lastError = error;
          }
        }

        return null;
      }

      var result = known.isEmpty ? null : await attempt([known]);
      result ??= await attempt(await _resolver.resolve(track));

      if (result == null) {
        throw lastError ?? StateError('Не удалось скачать аудио');
      }

      final (target, _) = result;

      String? artworkPath;
      if (track.artworkPath == null &&
          (track.thumbnailUrl?.isNotEmpty ?? false)) {
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
    // Не запускаем второй пакет поверх уже работающего.
    if (_batchRunning) return [];

    final list = tracks.toList();
    if (list.isEmpty) return [];

    final done = <Track>[];
    final active = <String, String>{};

    var cursor = 0;
    var completed = 0;
    var succeeded = 0;
    var failed = 0;

    _batchCanceled = false;
    _batchRunning = true;

    void publish() {
      _batchProgress.value = DownloadBatchProgress(
        total: list.length,
        completed: completed,
        succeeded: succeeded,
        failed: failed,
        currentTitles: active.values.toList(growable: false),
        canceled: _batchCanceled,
      );
    }

    publish();

    Future<void> worker() async {
      while (cursor < list.length && !_batchCanceled) {
        final track = list[cursor++];
        active[track.id] = track.title;
        publish();

        try {
          final downloaded = await download(track);

          if (downloaded.localPath != null &&
              downloaded.localPath!.isNotEmpty) {
            done.add(downloaded);
            succeeded++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        } finally {
          active.remove(track.id);
          completed++;

          publish();
          onProgress?.call(completed, list.length);
        }
      }
    }

    try {
      final workers =
          list.length < maxConcurrent ? list.length : maxConcurrent;

      await Future.wait(
        List.generate(workers, (_) => worker()),
      );

      return done;
    } finally {
      _batchRunning = false;
      publish();
    }
  }

  void cancel(String trackId) {
    final token = _tokens[trackId];
    if (token == null) return;

    if (!token.isCancelled) {
      token.cancel('cancelled');
    }
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
      track.copyWith(
        localPath: '',
        artworkPath: '',
        lyricsPath: '',
      ),
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
      if (await file.exists()) {
        total += await file.length();
      }
    }

    return total;
  }

  Future<void> _removeFile(String? path) async {
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _extensionOf(String url) {
    final uri = Uri.tryParse(url);
    final mime =
        uri?.queryParameters['mime'] ?? uri?.queryParameters['mimeType'];

    if (mime != null) {
      if (mime.contains('webm') || mime.contains('opus')) return 'opus';
      if (mime.contains('mp4') || mime.contains('m4a')) return 'm4a';
    }

    final segment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    final ext = p.extension(segment).replaceFirst('.', '').toLowerCase();

    if (['m4a', 'mp4', 'opus', 'webm', 'mp3'].contains(ext)) {
      return ext == 'webm' ? 'opus' : ext;
    }

    return 'm4a';
  }

  Future<void> _downloadFile(
    String url,
    File target,
    String trackId,
    CancelToken token,
  ) async {
    final response = await _dio.download(
      url,
      target.path,
      deleteOnError: true,
      cancelToken: token,
      options: Options(
        headers: _resolver.streamHeaders(url),
        validateStatus: (code) => code != null && code >= 200 && code < 300,
      ),
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

    final code = response.statusCode ?? 0;

    if (code != 200 && code != 206) {
      if (await target.exists()) {
        await target.delete();
      }
      throw HttpException('HTTP $code');
    }
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

        if (path != null && await File(path).exists()) {
          return path;
        }

        final fallback =
            p.join(_storage.lyricsDir.path, '${track.id}.lrc');

        await File(fallback).writeAsString(existing, flush: true);
        return fallback;
      }

      final lyrics = await _storage.fetchLyricsFromLrclib(track);

      if (lyrics == null || lyrics.isEmpty) return null;

      final lrc = lyrics.synced
          ? LrcParser.toLrc(
              lyrics,
              title: track.title,
              artist: track.artist,
            )
          : lyrics.plainText;

      final path = p.join(_storage.lyricsDir.path, '${track.id}.lrc');

      await File(path).writeAsString(lrc, flush: true);
      await _library.saveLyrics(track.id, lrc);

      return path;
    } catch (_) {
      return null;
    }
  }
}

class DownloadCanceled implements Exception {
  const DownloadCanceled();

  @override
  String toString() => 'Загрузка отменена';
}
