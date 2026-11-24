import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
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
import 'core/network/http_client.dart';
import 'core/network/split_proxy.dart';
import 'data/repositories/library_repository.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/audio_resolver_service.dart';
import 'services/download/download_service.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Локальное хранилище.
  await Hive.initFlutter();

  final settings = await Settings.open();

  // 2. Запускаем локальный прокси, если включён обход DPI.
  if (settings.bypassDpi) {
    try {
      await SplitProxy.shared.start().timeout(
        const Duration(seconds: 3),
      );
    } catch (error) {
      debugPrint('TrollMusic: SplitProxy startup failed: $error');
    }
  }

  HttpOverrides.global = BypassHttpOverrides(settings);

  final soundCloudCache = await Hive.openBox<dynamic>(
    SoundCloudService.cacheBoxName,
  );

  final library = await LibraryRepository.open();

  // 3. Сетевые сервисы.
  final lyrics = LyricsClient();

  final soundCloud = SoundCloudService(
    settings: settings,
    cache: soundCloudCache,
  );

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

  // 4. Хранилище и загрузки.
  final storage = await StorageService.open(
    library: library,
    lyrics: lyrics,
  );

  final downloads = DownloadService(
    library: library,
    storage: storage,
    resolver: resolver,
    settings: settings,
  );

  // 5. Инициализация audio_service.
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

  // 6. Подготавливаем зависимости приложения.
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

  // 7. Сначала показываем интерфейс.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TrollMusicApp(),
    ),
  );

  // 8. Восстановление путей и последнего трека — после первого кадра.
  unawaited(
    _runStartupTasks(
      storage: storage,
      audio: audio,
    ),
  );
}

/// Выполняет необязательные операции после запуска интерфейса.
/// Ошибка восстановления не должна блокировать приложение.
Future<void> _runStartupTasks({
  required StorageService storage,
  required TrollAudioHandler audio,
}) async {
  try {
    await storage.repairPaths();
  } catch (error, stack) {
    debugPrint('TrollMusic: repairPaths failed: $error');
    debugPrintStack(stackTrace: stack);
  }

  try {
    await audio.restoreLastPlayed().timeout(
      const Duration(seconds: 20),
    );
  } catch (error, stack) {
    debugPrint('TrollMusic: restoreLastPlayed failed: $error');
    debugPrintStack(stackTrace: stack);
  }
}