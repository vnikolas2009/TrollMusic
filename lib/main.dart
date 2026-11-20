import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/network_providers.dart';
import 'app/providers.dart';
import 'core/network/lyrics/lyrics_client.dart';
import 'core/network/piped/invidious_client.dart';
import 'core/network/piped/piped_client.dart';
import 'core/network/piped/youtube_music_client.dart';
import 'core/network/proxy.dart';
import 'core/storage/settings.dart';
import 'data/repositories/library_repository.dart';
import 'services/audio/audio_handler.dart';
import 'services/download/download_service.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  final settings = await Settings.open();
  final library = await LibraryRepository.open();

  final proxy = ProxyConfig(settings);
  final lyrics = LyricsClient();
  final piped = PipedClient(settings: settings, proxy: proxy);
  final invidious = InvidiousClient(settings: settings, proxy: proxy);
  final youtube = YouTubeMusicClient(piped: piped, invidious: invidious);

  final storage = await StorageService.open(library: library, lyrics: lyrics);
  final downloads = DownloadService(
    library: library,
    storage: storage,
    youtube: youtube,
  );

  final audio = await AudioService.init(
    builder: () => YsAudioHandler(
      library: library,
      settings: settings,
      resolveStream: youtube.streamUrl,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ysplayer.audio',
      androidNotificationChannelName: 'YSPlayer',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  await audio.init();
  await audio.restoreLastPlayed();

  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWithValue(settings),
      pipedClientProvider.overrideWithValue(piped),
      invidiousClientProvider.overrideWithValue(invidious),
      youtubeClientProvider.overrideWithValue(youtube),
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
      child: const YSPlayerApp(),
    ),
  );
}
