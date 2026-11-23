import 'dart:io';

import 'package:file_picker/file_picker.dart';

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
  const LyricsUpdate({
    required this.found,
    required this.synced,
    this.source,
  });

  final bool found;
  final bool synced;
  final LyricsSource? source;
}
