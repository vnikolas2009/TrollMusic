import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/lyrics/lyrics_client.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/path_repair.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

class StorageService {
  StorageService._({
    required Directory root,
    required LibraryRepository library,
    required LyricsClient lyrics,
  })  : _root = root,
        _library = library,
        _lyrics = lyrics;

  final Directory _root;
  final LibraryRepository _library;
  final LyricsClient _lyrics;

  static const _uuid = Uuid();

  static Future<StorageService> open({
    required LibraryRepository library,
    required LyricsClient lyrics,
  }) async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'trollmusic'));

    for (final sub in ['audio', 'artwork', 'lyrics', 'imports']) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }

    return StorageService._(
      root: root,
      library: library,
      lyrics: lyrics,
    );
  }

  Directory get root => _root;
  Directory get audioDir => Directory(p.join(_root.path, 'audio'));
  Directory get artworkDir => Directory(p.join(_root.path, 'artwork'));
  Directory get lyricsDir => Directory(p.join(_root.path, 'lyrics'));

  /// Чинит пути скачанных файлов после смены папки приложения (iOS).
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

  Future<void> clearCache() async {
    for (final track in _library.downloaded) {
      for (final path in [
        track.localPath,
        track.artworkPath,
        track.lyricsPath,
      ]) {
        if (path == null || path.isEmpty) continue;

        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await _library.saveTrack(
        track.copyWith(
          localPath: '',
          artworkPath: '',
          lyricsPath: '',
        ),
      );
    }
  }

  Future<Track> importLocalFile(
    File source, {
    String? sourcePath,
    int? sourceSize,
    int? sourceModifiedAtMs,
    String? existingTrackId,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException(
        'Исходный файл не существует',
        source.path,
      );
    }

    final existing = existingTrackId == null
        ? null
        : _library.trackById(existingTrackId);

    final id = existing?.id ?? 'local:${_uuid.v4()}';
    final extension = p.extension(source.path).toLowerCase();
    final target = File(p.join(audioDir.path, '$id$extension'));

    if (existing?.localPath != null &&
        existing!.localPath!.isNotEmpty &&
        existing.localPath != target.path) {
      final oldAudio = File(existing.localPath!);

      if (await oldAudio.exists()) {
        await oldAudio.delete();
      }
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
        '$id.${_imageExtension(picture.mimetype)}',
      );

      await File(artworkPath).writeAsBytes(
        picture.bytes,
        flush: true,
      );
    } else {
      artworkPath = existing?.artworkPath;
    }

    if (existing?.artworkPath != null &&
        existing!.artworkPath != artworkPath) {
      final oldArtwork = File(existing.artworkPath!);

      if (await oldArtwork.exists()) {
        await oldArtwork.delete();
      }
    }

    final track = Track(
      id: id,
      title: meta?.title ?? p.basenameWithoutExtension(source.path),
      artist: meta?.artist ??
          meta?.albumArtist ??
          'Неизвестный исполнитель',
      album: meta?.album ?? '',
      duration: meta?.duration ?? Duration.zero,
      localPath: target.path,
      artworkPath: artworkPath,
      source: TrackSource.local,
      bitrate: meta?.bitrate,
      sourcePath: sourcePath ?? existing?.sourcePath,
      sourceSize: sourceSize ?? existing?.sourceSize,
      sourceModifiedAtMs:
          sourceModifiedAtMs ?? existing?.sourceModifiedAtMs,
    );

    await _library.saveTrack(track);

    final embedded = meta?.lyrics;

    if (embedded != null && embedded.trim().isNotEmpty) {
      await _library.saveLyrics(track.id, embedded);
    }

    return track;
  }

  Future<Track?> attachArtworkFile(String trackId, File image) async {
    final track = _library.trackById(trackId);

    if (track == null) return null;

    final path = p.join(
      artworkDir.path,
      '$trackId${p.extension(image.path)}',
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

  Future<void> saveLyricsText(String trackId, String content) async {
    final path = p.join(lyricsDir.path, '$trackId.lrc');

    await File(path).writeAsString(
      content,
      flush: true,
    );

    await _library.saveLyrics(trackId, content);

    final track = _library.trackById(trackId);

    if (track != null) {
      await _library.saveTrack(
        track.copyWith(lyricsPath: path),
      );
    }
  }

  Future<Lyrics?> fetchLyricsFromLrclib(Track track) async {
    final lyrics = await _lyrics.get(
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    );

    if (lyrics == null || lyrics.isEmpty) return null;

    final lrc = lyrics.synced
        ? LrcParser.toLrc(
            lyrics,
            title: track.title,
            artist: track.artist,
          )
        : lyrics.plainText;

    await saveLyricsText(track.id, lrc);

    return lyrics;
  }

  String _imageExtension(String mime) => switch (mime.toLowerCase()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}
