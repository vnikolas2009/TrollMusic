import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/http_client.dart';
import '../core/network/lyrics/lyrics_client.dart';
import '../core/network/mirror_manager.dart';
import '../core/network/piped/invidious_client.dart';
import '../core/network/piped/piped_client.dart';
import '../core/network/piped/youtube_music_client.dart';
import '../core/network/proxy.dart';
import '../core/network/spotify/spotify_client.dart';
import '../core/network/worker_health.dart';
import '../core/storage/settings.dart';
import '../data/models/track.dart';
import '../data/repositories/music_repository.dart';

final dioProvider = Provider(
  (ref) => createDio(settings: ref.watch(settingsProvider)),
);

final settingsProvider = Provider<Settings>((ref) => throw UnimplementedError());

final proxyProvider = Provider<ProxyConfig>(
  (ref) => ProxyConfig(ref.watch(settingsProvider)),
);

final workerHealthProvider = Provider<WorkerHealth>(
  (ref) => WorkerHealth(
    settings: ref.watch(settingsProvider),
    proxy: ref.watch(proxyProvider),
  ),
);

final mirrorManagerProvider = Provider<MirrorManager>(
  (ref) => MirrorManager(
    settings: ref.watch(settingsProvider),
    dio: ref.watch(dioProvider),
    health: ref.watch(workerHealthProvider),
  ),
);

final pipedClientProvider = Provider<PipedClient>(
  (ref) => PipedClient(
    settings: ref.watch(settingsProvider),
    proxy: ref.watch(proxyProvider),
    health: ref.watch(workerHealthProvider),
  ),
);

final invidiousClientProvider = Provider<InvidiousClient>(
  (ref) => InvidiousClient(
    settings: ref.watch(settingsProvider),
    proxy: ref.watch(proxyProvider),
    health: ref.watch(workerHealthProvider),
  ),
);

final youtubeClientProvider = Provider<YouTubeMusicClient>(
  (ref) => YouTubeMusicClient(
    piped: ref.watch(pipedClientProvider),
    invidious: ref.watch(invidiousClientProvider),
    settings: ref.watch(settingsProvider),
    proxy: ref.watch(proxyProvider),
    health: ref.watch(workerHealthProvider),
  ),
);

final spotifyClientProvider = Provider<SpotifyClient>(
  (ref) => SpotifyClient(
    settings: ref.watch(settingsProvider),
    proxy: ref.watch(proxyProvider),
  ),
);

final lyricsClientProvider = Provider<LyricsClient>((ref) => LyricsClient());

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepository(
    youtube: ref.watch(youtubeClientProvider),
    spotify: ref.watch(spotifyClientProvider),
    lyrics: ref.watch(lyricsClientProvider),
  ),
);

/// Тренды для пустой медиатеки. Кэшируются до перезапуска приложения.
final trendingProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await ref.watch(youtubeClientProvider).trending();
  return tracks;
});
