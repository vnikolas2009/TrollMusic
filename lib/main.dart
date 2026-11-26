import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/settings_provider.dart';
import 'core/storage/settings.dart';
import 'data/repositories/library_repository.dart';
import 'services/audio/audio_handler.dart';
import 'services/fonts/font_service.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Локальное хранилище.
  await Hive.initFlutter();

  final settings = await Settings.open();
  final library = await LibraryRepository.open();
  final storage = await StorageService.open(library: library);

  // Пользовательские шрифты регистрируются до первого кадра, чтобы
  // интерфейс сразу открылся выбранным шрифтом. Сбой не критичен.
  try {
    await FontService(settings: settings, root: storage.root).loadSaved();
  } catch (error) {
    debugPrint('TrollMusic: loadSaved fonts failed: $error');
  }

  // 2. Инициализация audio_service.
  final audio = await AudioService.init(
    builder: () => TrollAudioHandler(
      library: library,
      settings: settings,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.trollmusic.audio',
      androidNotificationChannelName: 'TrollMusic',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  await audio.init();

  // 3. Зависимости приложения.
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWithValue(settings),
      servicesProvider.overrideWithValue(
        AppServices(
          library: library,
          storage: storage,
          audio: audio,
        ),
      ),
    ],
  );

  // 4. Сначала показываем интерфейс.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TrollMusicApp(),
    ),
  );

  // 5. Восстановление путей и последнего трека — после первого кадра.
  unawaited(
    _runStartupTasks(
      library: library,
      storage: storage,
      audio: audio,
    ),
  );
}

Future<void> _runStartupTasks({
  required LibraryRepository library,
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
    // Остатки стриминговых источников прошлых версий (записи без файла).
    await library.pruneUnplayable();
  } catch (error) {
    debugPrint('TrollMusic: pruneUnplayable failed: $error');
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