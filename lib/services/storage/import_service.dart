import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/config/app_config.dart';
import '../../core/network/artwork/artwork_search.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/lyrics_match.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../lyrics/lyrics_service.dart';
import 'storage_service.dart';

/// Импорт аудио и текстов в медиатеку.
class ImportService {
  ImportService({
    required LibraryRepository library,
    required StorageService storage,
    required LyricsService lyrics,
    ArtworkSearch? artwork,
  })  : _library = library,
        _storage = storage,
        _lyrics = lyrics,
        _artwork = artwork ?? ArtworkSearch();

  final LibraryRepository _library;
  final StorageService _storage;
  final LyricsService _lyrics;
  final ArtworkSearch _artwork;

  static final _audioSet = AppConfig.audioExtensions.toSet();
  static final _lyricsSet = AppConfig.lyricsExtensions.toSet();

  static String _ext(String path) =>
      p.extension(path).replaceFirst('.', '').toLowerCase();

  /// Выбор файлов: можно отметить сразу аудио и `.lrc` — тексты привяжутся
  /// к трекам по имени файла и тегам.
  Future<ImportResult> pickAndImport() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...AppConfig.audioExtensions,
        ...AppConfig.lyricsExtensions,
      ],
      dialogTitle: 'Импорт аудио и текстов',
    );
    if (files.isEmpty) return const ImportResult();

    final audio = <File>[];
    final lyrics = <File>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final ext = _ext(path);
      if (_audioSet.contains(ext)) {
        audio.add(File(path));
      } else if (_lyricsSet.contains(ext)) {
        lyrics.add(File(path));
      }
    }

    final imported = <Track>[];
    var attached = 0;
    final unpaired = [...lyrics];

    for (final file in audio) {
      final side = _takeSibling(file.path, unpaired);
      try {
        final track = await _storage.importLocalFile(file, lyricsFile: side);
        imported.add(track);
        if (side != null) attached++;
      } catch (_) {
        if (side != null) unpaired.add(side);
      }
    }

    attached += await _attachByMatching(unpaired);
    return ImportResult(tracks: imported, lyricsAttached: attached);
  }

  /// Добавляет в медиатеку уже скачанный файл (из встроенного браузера);
  /// временный файл после копирования удаляется.
  Future<Track> importDownloaded(File file) async {
    try {
      return await _storage.importLocalFile(file);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Выбор только файлов с текстами для уже импортированных треков.
  Future<ImportResult> pickAndImportLyrics() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.lyricsExtensions,
      dialogTitle: 'Выберите файлы с текстами',
    );
    if (files.isEmpty) return const ImportResult();

    final list = <File>[
      for (final f in files)
        if (f.path != null) File(f.path!),
    ];
    final attached = await _attachByMatching(list);
    return ImportResult(lyricsAttached: attached, lyricsSkipped: list.length - attached);
  }

  /// Забирает из [candidates] файл с текстом, лежащий рядом с [audioPath]
  /// и называющийся так же.
  File? _takeSibling(String audioPath, List<File> candidates) {
    final dir = p.dirname(audioPath);
    final name = p.basenameWithoutExtension(audioPath).toLowerCase();
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (p.dirname(c.path) == dir &&
          p.basenameWithoutExtension(c.path).toLowerCase() == name) {
        return candidates.removeAt(i);
      }
    }
    return null;
  }

  /// Привязывает файлы с текстами к трекам медиатеки по названию/исполнителю
  /// (из имени файла или тегов `[ti:]`, `[ar:]`). Возвращает число привязанных.
  Future<int> _attachByMatching(List<File> files) async {
    if (files.isEmpty) return 0;
    final tracks = _library.tracks;
    var attached = 0;

    for (final file in files) {
      try {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) continue;
        final track = _matchTrack(p.basenameWithoutExtension(file.path), raw, tracks);
        if (track == null) continue;
        await _storage.saveLyricsText(track.id, raw);
        attached++;
      } catch (_) {
        continue;
      }
    }
    return attached;
  }

  Track? _matchTrack(String fileName, String content, List<Track> tracks) {
    for (final track in tracks) {
      if (lyricsFileMatchesTrack(
        lyricsFileName: fileName,
        title: track.title,
        artist: track.artist,
        audioFileName: track.sourcePath == null
            ? ''
            : p.basenameWithoutExtension(track.sourcePath!),
      )) {
        return track;
      }
    }
    final meta = LrcParser.readMeta(content);
    final title = meta.title;
    if (title == null) return null;
    final label = meta.artist == null ? title : '${meta.artist} - $title';
    for (final track in tracks) {
      if (lyricsFileMatchesTrack(
        lyricsFileName: label,
        title: track.title,
        artist: track.artist,
      )) {
        return track;
      }
    }
    return null;
  }

  Future<Track?> importLyricsFromFile(String trackId) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: AppConfig.lyricsExtensions,
      dialogTitle: 'Выбрать текст',
    );
    final path = file?.path;
    if (path == null) return null;
    return _storage.attachLyricsFile(trackId, File(path));
  }

  /// Привязывает уже выбранную картинку (из медиатеки или файлов).
  Future<Track?> importArtworkFromPath(String trackId, String path) =>
      _storage.attachArtworkFile(trackId, File(path));

  /// Ищет обложку в интернете по исполнителю и названию. `null` — уверенного
  /// совпадения нет или сеть недоступна.
  Future<Track?> findArtworkOnline(Track track) async {
    final bytes = await _artwork.findCover(
      title: track.title,
      artist: track.artist,
      album: track.album,
    );
    if (bytes == null) return null;

    final dir = await Directory.systemTemp.createTemp('cover_');
    try {
      final file = File(p.join(dir.path, 'cover.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      return await _storage.attachArtworkFile(track.id, file);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Ищет обложки в интернете для всех треков без обложки. [onProgress]
  /// получает (обработано, всего, найдено); [isCancelled] позволяет
  /// остановить поиск. Возвращает число найденных обложек.
  Future<int> findMissingArtwork({
    void Function(int done, int total, int found)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final missing = [
      for (final t in _library.tracks)
        if (t.artworkPath == null || t.artworkPath!.isEmpty || !File(t.artworkPath!).existsSync()) t,
    ];
    var found = 0;
    for (var i = 0; i < missing.length; i++) {
      if (isCancelled?.call() ?? false) break;
      try {
        if (await findArtworkOnline(missing[i]) != null) found++;
      } catch (_) {
        // Один сбой сети не должен останавливать весь поиск.
      }
      onProgress?.call(i + 1, missing.length, found);
      // iTunes ограничивает частоту запросов (около 20 в минуту).
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return found;
  }

  /// Ищет текст в сети и сохраняет. [provider] — идентификатор источника
  /// (`lrclib`, `kugou`, `qq`, `ovh`); без него перебираются все.
  Future<LyricsUpdate> findLyricsOnline(Track track, {String? provider}) async {
    final found = await _lyrics.find(
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationSec: track.duration.inSeconds,
      onlyProvider: provider,
    );
    if (found == null) return const LyricsUpdate(found: false);

    await _storage.saveLyricsText(track.id, found.text);
    return LyricsUpdate(
      found: true,
      synced: found.synced,
      wordSynced: found.wordSynced,
      source: found.source,
    );
  }

  Future<void> saveManualLyrics(String trackId, String text) =>
      _storage.saveLyricsText(trackId, text);

  Future<void> updateTags(
    String trackId, {
    String? title,
    String? artist,
    String? album,
  }) =>
      _library.updateMetadata(trackId, title: title, artist: artist, album: album);
}

class ImportResult {
  const ImportResult({
    this.tracks = const [],
    this.lyricsAttached = 0,
    this.lyricsSkipped = 0,
  });

  final List<Track> tracks;
  final int lyricsAttached;
  final int lyricsSkipped;
}

class LyricsUpdate {
  const LyricsUpdate({
    required this.found,
    this.synced = false,
    this.wordSynced = false,
    this.source,
  });

  final bool found;
  final bool synced;
  final bool wordSynced;
  final String? source;
}
