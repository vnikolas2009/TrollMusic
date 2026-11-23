import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/network_providers.dart';
import 'app/providers.dart';
import 'core/network/audius/audius_service.dart';
import 'core/network/lyrics/lyrics_client.dart';
import 'core/network/soundcloud/soundcloud_service.dart';
import 'core/network/vk/vk_music_service.dart';
import 'core/network/yandex/yandex_music_service.dart';
import 'core/network/youtube/innertube_service.dart';
import 'core/storage/settings.dart';
import 'data/repositories/library_repository.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/audio_resolver_service.dart';
import 'services/download/download_service.dart';
import 'core/network/split_proxy.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  final settings = await Settings.open();
  if (settings.bypassDpi) await SplitProxy.shared.start();
  final soundCloudCache = await Hive.openBox<dynamic>(SoundCloudService.cacheBoxName);
  final library = await LibraryRepository.open();

  final lyrics = LyricsClient();
  final soundCloud = SoundCloudService(settings: settings, cache: soundCloudCache);
  final innerTube = InnerTubeService(settings: settings);
  final yandex = YandexMusicService(settings: settings);
  final vk = VkMusicService(settings: settings);
  final audius = AudiusService(settings: settings);
  final resolver = AudioResolverService(
    soundcloud: soundCloud,
    innerTube: innerTube,
    yandex: yandex,
    vk: vk,
    audius: audius,
  );

  final storage = await StorageService.open(library: library, lyrics: lyrics);
  final downloads = DownloadService(
    library: library,
    storage: storage,
    resolver: resolver,
    settings: settings,
  );

  final audio = await AudioService.init(
    builder: () => TrollAudioHandler(
      library: library,
      settings: settings,
      resolver: resolver,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.trollmusic.audio',
      androidNotificationChannelName: 'TrollMusic',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  await audio.init();
  await audio.restoreLastPlayed();

  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWithValue(settings),
      soundCloudServiceProvider.overrideWithValue(soundCloud),
      innerTubeServiceProvider.overrideWithValue(innerTube),
      yandexMusicServiceProvider.overrideWithValue(yandex),
      vkMusicServiceProvider.overrideWithValue(vk),
      audiusServiceProvider.overrideWithValue(audius),
      audioResolverProvider.overrideWithValue(resolver),
      lyricsClientProvider.overrideWithValue(lyrics),
      servicesProvider.overrideWithValue(
        AppServices(
          library: library,
          storage: storage,
          downloads: downloads,
          audio: audio,
        ),
      ),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TrollMusicApp(),
    ),
  );
}
