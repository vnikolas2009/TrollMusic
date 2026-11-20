import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/lyrics/lyrics_client.dart';
import '../../core/utils/lrc_parser.dart';
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
    final root = Directory(p.join(base.path, 'ysplayer'));
    for (final sub in ['audio', 'artwork', 'lyrics', 'imports']) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }
    return StorageService._(root: root, library: library, lyrics: lyrics);
  }

  Directory get root => _root;
  Directory get audioDir => Directory(p.join(_root.path, 'audio'));
  Directory get artworkDir => Directory(p.join(_root.path, 'artwork'));
  Directory get lyricsDir => Directory(p.join(_root.path, 'lyrics'));

  Future<int> usedBytes() async {
    if (!await _root.exists()) return 0;
    var total = 0;
    await for (final entity in _root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    for (final dir in [audioDir, artworkDir, lyricsDir]) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) await entity.delete();
      }
    }
    for (final track in _library.downloaded) {
      await _library.saveTrack(track.copyWith(localPath: '', lyricsPath: ''));
    }
  }

  Future<Track> importLocalFile(File source) async {
    final id = 'local:${_uuid.v4()}';
    final extension = p.extension(source.path).toLowerCase();
    final target = File(p.join(audioDir.path, '$id$extension'));
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
      artworkPath = p.join(artworkDir.path, '$id.${_imageExtension(picture.mimetype)}');
      await File(artworkPath).writeAsBytes(picture.bytes, flush: true);
    }

    final track = Track(
      id: id,
      title: meta?.title ?? p.basenameWithoutExtension(source.path),
      artist: meta?.artist ?? meta?.albumArtist ?? 'Неизвестный исполнитель',
      album: meta?.album ?? '',
      duration: meta?.duration ?? Duration.zero,
      localPath: target.path,
      artworkPath: artworkPath,
      source: TrackSource.local,
      bitrate: meta?.bitrate,
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
    final path = p.join(artworkDir.path, '$trackId${p.extension(image.path)}');
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
    await File(path).writeAsString(content, flush: true);
    await _library.saveLyrics(trackId, content);
    final track = _library.trackById(trackId);
    if (track != null) {
      await _library.saveTrack(track.copyWith(lyricsPath: path));
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
        ? LrcParser.toLrc(lyrics, title: track.title, artist: track.artist)
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
