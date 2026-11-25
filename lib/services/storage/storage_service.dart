import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/lyrics_match.dart';
import '../../core/utils/path_repair.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

/// Файлы приложения: копии аудио, обложки и тексты, а также импорт треков.
class StorageService {
  StorageService._({
    required Directory root,
    required LibraryRepository library,
  })  : _root = root,
        _library = library;

  final Directory _root;
  final LibraryRepository _library;

  static const _uuid = Uuid();

  static Future<StorageService> open({
    required LibraryRepository library,
  }) async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'trollmusic'));

    for (final sub in ['audio', 'artwork', 'lyrics']) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }

    return StorageService._(root: root, library: library);
  }

  Directory get root => _root;
  Directory get audioDir => Directory(p.join(_root.path, 'audio'));
  Directory get artworkDir => Directory(p.join(_root.path, 'artwork'));
  Directory get lyricsDir => Directory(p.join(_root.path, 'lyrics'));

  /// Чинит пути файлов после смены папки приложения (iOS).
  Future<int> repairPaths() async {
    var fixed = 0;
    for (final track in _library.tracks) {
      final audio = repairedPath(track.localPath, _root.path);
      final art = repairedPath(track.artworkPath, _root.path);
      final lyr = repairedPath(track.lyricsPath, _root.path);
      if (audio == null && art == null && lyr == null) continue;
      await _library.saveTrack(
        track.copyWith(localPath: audio, artworkPath: art, lyricsPath: lyr),
      );
      fixed++;
    }
    return fixed;
  }

  Future<int> usedBytes() async {
    if (!await _root.exists()) return 0;

    var total = 0;
    await for (final entity
        in _root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Удаляет трек вместе с файлами аудио, обложки и текста.
  Future<void> deleteTrack(String id) async {
    final track = _library.trackById(id);
    if (track != null) {
      for (final path in [track.localPath, track.artworkPath, track.lyricsPath]) {
        await _deleteQuietly(path);
      }
    }
    await _library.deleteTrack(id);
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Копирует файл в хранилище, читает теги и сохраняет трек.
  ///
  /// [lyricsFile] — готовый файл с текстом (`.lrc` рядом с аудио). Если его нет,
  /// берётся текст из тегов файла. Название и исполнитель без тегов
  /// определяются по имени файла («Артист - Название.mp3»).
  Future<Track> importLocalFile(
    File source, {
    String? sourcePath,
    int? sourceSize,
    int? sourceModifiedAtMs,
    String? existingTrackId,
    File? lyricsFile,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException('Исходный файл не существует', source.path);
    }

    final existing =
        existingTrackId == null ? null : _library.trackById(existingTrackId);

    final id = existing?.id ?? 'local:${_uuid.v4()}';
    final extension = p.extension(source.path).toLowerCase();
    final target = File(p.join(audioDir.path, '${_safe(id)}$extension'));

    if (existing?.localPath != null &&
        existing!.localPath!.isNotEmpty &&
        existing.localPath != target.path) {
      await _deleteQuietly(existing.localPath);
    }

    await source.copy(target.path);

    AudioMetadata? meta;
    try {
      meta = readMetadata(target, getImage: true);
    } catch (_) {
      meta = null;
    }

    String? artworkPath;
    final pictures = meta?.pictures ?? const <Picture>[];
    if (pictures.isNotEmpty) {
      final picture = pictures.first;
      artworkPath = p.join(
        artworkDir.path,
        '${_safe(id)}.${_imageExtension(picture.mimetype)}',
      );
      await File(artworkPath).writeAsBytes(picture.bytes, flush: true);
    } else {
      artworkPath = existing?.artworkPath;
    }

    if (existing?.artworkPath != null &&
        existing!.artworkPath != artworkPath) {
      await _deleteQuietly(existing.artworkPath);
    }

    final rawTitle = (meta?.title ?? '').trim();
    final rawArtist = (meta?.artist ?? meta?.albumArtist ?? '').trim();
    final fallbackTitle = p.basenameWithoutExtension(source.path);
    final named = splitArtistFromTitle(
      rawTitle.isEmpty ? fallbackTitle : rawTitle,
      rawArtist,
    );

    final track = Track(
      id: id,
      title: named.title.isEmpty ? fallbackTitle : named.title,
      artist: named.artist.trim().isEmpty ? unknownArtist : named.artist.trim(),
      album: meta?.album ?? '',
      duration: meta?.duration ?? Duration.zero,
      localPath: target.path,
      artworkPath: artworkPath,
      bitrate: meta?.bitrate,
      addedAtMs: existing?.addedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      sourcePath: sourcePath ?? existing?.sourcePath,
      sourceSize: sourceSize ?? existing?.sourceSize,
      sourceModifiedAtMs: sourceModifiedAtMs ?? existing?.sourceModifiedAtMs,
    );

    await _library.saveTrack(track);

    // Текст: сначала файл рядом с аудио, затем теги. Уже сохранённый текст
    // (например, найденный в сети) при повторном сканировании не затирается.
    String? lyrics;
    if (lyricsFile != null) {
      try {
        lyrics = await lyricsFile.readAsString();
      } catch (_) {
        lyrics = null;
      }
    }
    lyrics ??= meta?.lyrics;

    if (lyrics != null && lyrics.trim().isNotEmpty) {
      await saveLyricsText(track.id, lyrics);
    }

    return _library.trackById(track.id) ?? track;
  }

  Future<Track?> attachArtworkFile(String trackId, File image) async {
    final track = _library.trackById(trackId);
    if (track == null) return null;

    final path = p.join(
      artworkDir.path,
      '${_safe(trackId)}${p.extension(image.path)}',
    );
    await image.copy(path);

    final updated = track.copyWith(artworkPath: path);
    await _library.saveTrack(updated);
    return updated;
  }

  Future<Track?> attachLyricsFile(String trackId, File file) async {
    final raw = await file.readAsString();
    await saveLyricsText(trackId, raw);
    return _library.trackById(trackId);
  }

  /// Сохраняет текст (LRC, enhanced LRC или обычный) в файл и в базу.
  Future<void> saveLyricsText(String trackId, String content) async {
    final text = content.replaceAll('﻿', '').trim();
    if (text.isEmpty) return;

    final path = p.join(lyricsDir.path, '${_safe(trackId)}.lrc');
    await File(path).writeAsString(text, flush: true);
    await _library.saveLyrics(trackId, text);

    final track = _library.trackById(trackId);
    if (track != null && track.lyricsPath != path) {
      await _library.saveTrack(track.copyWith(lyricsPath: path));
    }
  }

  /// Идентификатор содержит `:`, а в имени файла он нежелателен.
  String _safe(String id) => safeFileName(id);

  String _imageExtension(String mime) => switch (mime.toLowerCase()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}
