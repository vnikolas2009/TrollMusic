import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'storage_service.dart';

class ImportService {
  ImportService({
    required LibraryRepository library,
    required StorageService storage,
  })  : _library = library,
        _storage = storage;

  final LibraryRepository _library;
  final StorageService _storage;

  static const audioExtensions = ['mp3', 'm4a', 'flac', 'wav', 'ogg', 'opus', 'aac'];

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
      imported.add(await _storage.importLocalFile(File(path)));
    }
    return imported;
  }

  Future<Track?> importLyricsFromFile(String trackId) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
      dialogTitle: 'Выбрать текст',
    );
    final path = file?.path;
    if (path == null) return null;
    return _storage.attachLyricsFile(trackId, File(path));
  }

  Future<Track?> importArtworkFromFile(String trackId) async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: 'Выбрать обложку',
    );
    final path = file?.path;
    if (path == null) return null;
    return _storage.attachArtworkFile(trackId, File(path));
  }

  Future<LyricsUpdate> findLyricsOnline(Track track) async {
    final lyrics = await _storage.fetchLyricsFromLrclib(track);
    return LyricsUpdate(
      found: lyrics != null && !lyrics.isEmpty,
      synced: lyrics?.synced ?? false,
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
      _library.updateMetadata(
        trackId,
        title: title,
        artist: artist,
        album: album,
      );
}

class LyricsUpdate {
  const LyricsUpdate({required this.found, required this.synced});

  final bool found;
  final bool synced;
}
