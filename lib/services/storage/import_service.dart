import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/network/lyrics/external_lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'storage_service.dart';

class ImportService {
  ImportService({
    required LibraryRepository library,
    required StorageService storage,
    ExternalLyricsClient? external,
    String Function()? geniusToken,
  })  : _library = library,
        _storage = storage,
        _external = external,
        _geniusToken = geniusToken;

  final ExternalLyricsClient? _external;
  final String Function()? _geniusToken;

  final LibraryRepository _library;
  final StorageService _storage;

  static const audioExtensions = [
    'mp3',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'opus',
    'aac',
  ];

  Future<List<Track>> pickAndImportAudio() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioExtensions,
      dialogTitle: 'Импорт аудио',
    );

    if (files.isEmpty) return const [];

    final imported = <Track>[];

    for (final file in files) {
      final path = file.path;

      if (path == null) continue;

      imported.add(
        await _storage.importLocalFile(File(path)),
      );
    }

    return imported;
  }

  /// Выбирает папку и сканирует её вместе со всеми вложенными папками.
  ///
  /// fullRescan = false:
  /// пропускает файлы, которые не изменились после прошлого сканирования.
  ///
  /// fullRescan = true:
  /// повторно читает метаданные всех найденных аудиофайлов.
  Future<FolderScanResult?> scanFolder({
    required bool fullRescan,
  }) async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку с музыкой',
    );

    if (selectedPath == null || selectedPath.isEmpty) {
      return null;
    }

    final root = Directory(selectedPath);

    if (!await root.exists()) {
      throw FileSystemException(
        'Выбранная папка не существует',
        selectedPath,
      );
    }

    final existingByPath = <String, Track>{};

    for (final track in _library.local) {
      final sourcePath = track.sourcePath;

      if (sourcePath == null || sourcePath.isEmpty) continue;

      existingByPath[p.normalize(sourcePath)] = track;
    }

    final pendingDirectories = <Directory>[root];

    var scanned = 0;
    var added = 0;
    var updated = 0;
    var skipped = 0;
    var errors = 0;

    while (pendingDirectories.isNotEmpty) {
      final directory = pendingDirectories.removeLast();

      try {
        await for (final entity
            in directory.list(followLinks: false)) {
          if (entity is Directory) {
            pendingDirectories.add(entity);
            continue;
          }

          if (entity is! File) continue;

          final extension = p
              .extension(entity.path)
              .replaceFirst('.', '')
              .toLowerCase();

          if (!audioExtensions.contains(extension)) continue;

          scanned++;

          try {
            final absolutePath = p.normalize(
              entity.absolute.path,
            );

            final stat = await entity.stat();

            final existing = existingByPath[absolutePath];

            final unchanged = existing != null &&
                existing.sourceSize == stat.size &&
                existing.sourceModifiedAtMs ==
                    stat.modified.millisecondsSinceEpoch;

            if (!fullRescan && unchanged) {
              skipped++;
              continue;
            }

            await _storage.importLocalFile(
              entity,
              sourcePath: absolutePath,
              sourceSize: stat.size,
              sourceModifiedAtMs:
                  stat.modified.millisecondsSinceEpoch,
              existingTrackId: existing?.id,
            );

            if (existing == null) {
              added++;
            } else {
              updated++;
            }
          } catch (_) {
            errors++;
          }
        }
      } catch (_) {
        errors++;
      }
    }

    return FolderScanResult(
      scanned: scanned,
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
      fullRescan: fullRescan,
    );
  }

  Future<Track?> importLyricsFromFile(String trackId) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
      dialogTitle: 'Выбрать текст',
    );

    final path = file?.path;

    if (path == null) return null;

    return _storage.attachLyricsFile(
      trackId,
      File(path),
    );
  }

  Future<Track?> importArtworkFromFile(String trackId) async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: 'Выбрать обложку',
    );

    final path = file?.path;

    if (path == null) return null;

    return _storage.attachArtworkFile(
      trackId,
      File(path),
    );
  }

  /// Ищет текст. Без [source] перебирает LRCLIB → Lyrics.ovh → Genius
  /// (последний — только если в настройках задан токен).
  Future<LyricsUpdate> findLyricsOnline(
    Track track, {
    LyricsSource? source,
  }) async {
    final order = source != null
        ? [source]
        : const [
            LyricsSource.lrclib,
            LyricsSource.lyricsify,
            LyricsSource.lyricsOvh,
            LyricsSource.genius,
          ];

    for (final candidate in order) {
      switch (candidate) {
        case LyricsSource.lrclib:
          final lyrics = await _storage.fetchLyricsFromLrclib(track);
          if (lyrics != null && !lyrics.isEmpty) {
            return LyricsUpdate(
              found: true,
              synced: lyrics.synced,
              source: candidate,
            );
          }
        case LyricsSource.lyricsify:
          final lrc = await _external?.lyricsify(
            artist: track.artist.split(',').first,
            title: track.title,
          );
          if (lrc != null) {
            await _storage.saveLyricsText(track.id, lrc);
            return LyricsUpdate(found: true, synced: true, source: candidate);
          }
        case LyricsSource.lyricsOvh:
          final text = await _external?.lyricsOvh(
            artist: track.artist.split(',').first,
            title: track.title,
          );
          if (text != null) {
            await _storage.saveLyricsText(track.id, text);
            return LyricsUpdate(found: true, synced: false, source: candidate);
          }
        case LyricsSource.genius:
          final text = await _external?.genius(
            token: _geniusToken?.call() ?? '',
            artist: track.artist.split(',').first,
            title: track.title,
          );
          if (text != null) {
            await _storage.saveLyricsText(track.id, text);
            return LyricsUpdate(found: true, synced: false, source: candidate);
          }
      }
    }
    return const LyricsUpdate(found: false, synced: false);
  }

  /// Импорт текста по ссылке на страницу песни Lyricsify.
  Future<bool> importLyricsifyUrl(String trackId, String url) async {
    final lrc = await _external?.lyricsifyUrl(url);
    if (lrc == null) return false;
    await _storage.saveLyricsText(trackId, lrc);
    return true;
  }

  Future<void> saveManualLyrics(
    String trackId,
    String text,
  ) =>
      _storage.saveLyricsText(trackId, text);

  Future<void> updateTags(
    String trackId, {
    String? title,
    String? artist,
    String? album,
  }) =>
      _library.updateMetadata(
        trackId,
        title: title,
        artist: artist,
        album: album,
      );
}

class FolderScanResult {
  const FolderScanResult({
    required this.scanned,
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
    required this.fullRescan,
  });

  final int scanned;
  final int added;
  final int updated;
  final int skipped;
  final int errors;
  final bool fullRescan;
}

class LyricsUpdate {
  const LyricsUpdate({
    required this.found,
    required this.synced,
    this.source,
  });

  final bool found;
  final bool synced;
  final LyricsSource? source;
}
