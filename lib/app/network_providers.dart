import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/config/app_config.dart';
import '../core/network/audius/audius_service.dart';
import '../core/network/http_client.dart';
import '../core/network/lyrics/external_lyrics.dart';
import '../core/network/lyrics/lyrics_client.dart';
import '../core/network/soundcloud/soundcloud_service.dart';
import '../core/network/spotify/spotify_client.dart';
import '../core/network/vk/vk_music_service.dart';
import '../core/network/yandex/yandex_music_service.dart';
import '../core/network/youtube/innertube_service.dart';
import '../core/storage/settings.dart';
import '../data/models/track.dart';
import '../data/repositories/music_repository.dart';
import '../services/audio/audio_resolver_service.dart';

final dioProvider = Provider(
  (ref) => createDio(settings: ref.watch(settingsProvider)),
);

final settingsProvider = Provider<Settings>((ref) => throw UnimplementedError());

final soundCloudServiceProvider = Provider<SoundCloudService>(
  (ref) => SoundCloudService(
    settings: ref.watch(settingsProvider),
    cache: Hive.box<dynamic>(SoundCloudService.cacheBoxName),
  ),
);

final innerTubeServiceProvider = Provider<InnerTubeService>(
  (ref) => InnerTubeService(settings: ref.watch(settingsProvider)),
);

final yandexMusicServiceProvider = Provider<YandexMusicService>(
  (ref) => YandexMusicService(settings: ref.watch(settingsProvider)),
);

final vkMusicServiceProvider = Provider<VkMusicService>(
  (ref) => VkMusicService(settings: ref.watch(settingsProvider)),
);

final audiusServiceProvider = Provider<AudiusService>(
  (ref) => AudiusService(settings: ref.watch(settingsProvider)),
);

final audioResolverProvider = Provider<AudioResolverService>(
  (ref) => AudioResolverService(
    soundcloud: ref.watch(soundCloudServiceProvider),
    innerTube: ref.watch(innerTubeServiceProvider),
    yandex: ref.watch(yandexMusicServiceProvider),
    vk: ref.watch(vkMusicServiceProvider),
    audius: ref.watch(audiusServiceProvider),
  ),
);

final spotifyClientProvider = Provider<SpotifyClient>(
  (ref) => SpotifyClient(settings: ref.watch(settingsProvider)),
);

final lyricsClientProvider = Provider<LyricsClient>((ref) => LyricsClient());

final externalLyricsProvider = Provider<ExternalLyricsClient>(
  (ref) => ExternalLyricsClient(dio: ref.watch(dioProvider)),
);

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepository(
    resolver: ref.watch(audioResolverProvider),
    spotify: ref.watch(spotifyClientProvider),
    lyrics: ref.watch(lyricsClientProvider),
  ),
);

/// Популярное в Spotify (метаданные Spotify, воспроизведение — через YouTube).
final spotifyTrendingProvider = FutureProvider<List<Track>>((ref) {
  return ref.watch(musicRepositoryProvider).spotifyMix(AppConfig.spotifyQueries);
});

/// Тренды для пустой медиатеки. Кэшируются до перезапуска приложения.
final trendingProvider = FutureProvider<List<Track>>((ref) async {
  return ref.watch(audioResolverProvider).trending();
});
