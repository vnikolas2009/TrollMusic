import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/playlist.dart';
import '../data/models/track.dart';
import '../data/repositories/library_repository.dart';
import '../services/audio/audio_handler.dart';
import '../services/storage/import_service.dart';
import '../services/storage/storage_service.dart';
import 'settings_provider.dart';

class AppServices {
  AppServices({
    required this.library,
    required this.storage,
    required this.audio,
  });

  final LibraryRepository library;
  final StorageService storage;
  final TrollAudioHandler audio;
}

final servicesProvider = Provider<AppServices>((ref) => throw UnimplementedError());

final libraryProvider = Provider<LibraryRepository>(
  (ref) => ref.watch(servicesProvider).library,
);

final storageProvider = Provider<StorageService>(
  (ref) => ref.watch(servicesProvider).storage,
);

final importProvider = Provider<ImportService>(
  (ref) => ImportService(
    library: ref.watch(libraryProvider),
    storage: ref.watch(storageProvider),
    lyrics: ref.watch(lyricsServiceProvider),
  ),
);

final audioHandlerProvider = Provider<TrollAudioHandler>(
  (ref) => ref.watch(servicesProvider).audio,
);

final tracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(libraryProvider).tracksStream,
);
final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(libraryProvider).playlistsStream,
);

final likedProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(libraryProvider).tracksStream.map((_) => ref.read(libraryProvider).liked),
);

final currentTrackProvider = StreamProvider<Track?>((ref) {
  final library = ref.watch(libraryProvider);
  final audio = ref.watch(audioHandlerProvider);
  return audio.mediaItem.map((item) {
    if (item == null) return null;
    return library.trackById(item.id) ??
        Track(
          id: item.id,
          title: item.title,
          artist: item.artist ?? '',
          album: item.album ?? '',
          duration: item.duration ?? Duration.zero,
          artworkPath: item.artUri?.toFilePath(),
        );
  });
});

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);

final durationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(audioHandlerProvider).durationStream,
);

/// Докачанная часть трека для серой полосы на ползунке. Слушать только в
/// узких виджетах (как и `positionProvider`).
final bufferedPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).bufferedPositionStream,
);

final audioErrorsProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
);
