# YSPlayer — архитектура

Flutter-приложение (iOS/Android). Состояние — Riverpod, хранилище — Hive, звук — just_audio + audio_service. Каталог берётся с YouTube (через зеркала Piped/Invidious) и Spotify (embed/API, без ключей); тексты — LRCLIB. Локального Flutter в окружении разработки нет: **единственная проверка компиляции — CI** (`.github/workflows/build_release.yml`).

## 1. Слои и карта файлов

```
lib/
  main.dart                  # сборка зависимостей вручную → ProviderContainer (overrides) → runApp
  app/
    app.dart                 # MaterialApp (YSPlayerApp)
    app_shell.dart           # IndexedStack вкладок + MiniPlayer + YsBottomNav
    providers.dart           # AppServices, провайдеры библиотеки/плеера (Stream/Provider)
    network_providers.dart   # провайдеры сети: dio, settings, proxy, mirrors, клиенты, MusicRepository
  core/
    config/app_config.dart   # таймауты, списки зеркал по умолчанию, битрейты
    network/
      http_client.dart       # createDio()
      http_overrides.dart    # AppHttpOverrides: глобальный HTTP-прокси (findProxy из Settings.httpProxy)
      proxy.dart             # ProxyConfig: строит URL (напрямую / через Worker), см. §4
      mirror_manager.dart    # перебор зеркал Piped/Invidious, cooldown 2 мин, запасной проход через Worker
      piped/{piped,invidious,youtube_music}_client.dart
      spotify/spotify_client.dart
      lyrics/lyrics_client.dart   # LRCLIB
    storage/settings.dart    # Hive-box 'settings' (типизированные геттеры/сеттеры)
    theme/{app_theme,app_colors}.dart
    utils/                   # ЧИСТЫЕ функции (покрываются тестами): lrc_parser, track_groups,
                             # track_search, track_match, spotify_link, proxy_address, formatters, permission_service
  data/
    models/{track,playlist,lyrics,artist}.dart
    repositories/
      library_repository.dart  # Hive: треки, плейлисты, лайки, тексты, JSON-бэкап
      music_repository.dart    # поиск (YouTube + Spotify), импорт Spotify-ссылок, тексты
  services/
    audio/audio_handler.dart   # YsAudioHandler (BaseAudioHandler): очередь, кроссфейд, таймер сна, скорость
    download/download_service.dart  # офлайн-загрузки (прогресс, отмена, лимит параллельности)
    storage/storage_service.dart    # файлы: импорт локальных, обложки, .lrc, кэш
    storage/import_service.dart     # фасад для UI: теги, тексты из файла/LRCLIB
  features/                  # экраны: home, search, library, playlist, artist, player, lyrics,
                             # create (+backup, track_edit_sheet), settings
  shared/widgets/            # track_tile, mini_player, ys_bottom_nav, station_card, cover_art, ...
worker.js                    # Cloudflare Worker (reverse proxy), деплоится отдельно
test/                        # flutter test: чистые утилиты, модели, config, виджет-смоук
```

Правило слоёв: `features/shared` → `app` (провайдеры) → `services/data` → `core`. `core/utils` не зависит от Flutter-UI и Riverpod.

## 2. Инициализация и DI

`main.dart` без DI-контейнера создаёт объекты **вручную** и передаёт в `ProviderContainer(overrides: ...)`:

`Hive.initFlutter → Settings.open → HttpOverrides.global = AppHttpOverrides(settings) → LibraryRepository.open → ProxyConfig/LyricsClient/Piped/Invidious/YouTubeMusicClient → StorageService.open → DownloadService → AudioService.init(YsAudioHandler(resolveStream: youtube.streamUrlForTrack)) → restoreLastPlayed`.

Провайдеры с `throw UnimplementedError()` (`servicesProvider`, `settingsProvider`, …) **обязательно** переопределяются в `main`. Новый сервис = создать в `main`, добавить в `AppServices`/override и провайдер. Остальные сетевые провайдеры (`spotifyClientProvider`, `musicRepositoryProvider`, `mirrorManagerProvider`, `trendingProvider`) строятся лениво в `network_providers.dart`.

Ключевые провайдеры (`providers.dart`): `libraryProvider`, `storageProvider`, `downloadProvider`, `importProvider`, `audioHandlerProvider`; потоки `tracksProvider`, `downloadedProvider`, `localTracksProvider`, `playlistsProvider`, `likedProvider`, `currentTrackProvider`, `playbackStateProvider`, `positionProvider`, `durationProvider`, `audioErrorsProvider`.

## 3. Данные

**Track** (`data/models/track.dart`): `id, title, artist, album, duration, thumbnailUrl, streamUrl, localPath, lyricsPath, artworkPath, explicit, source (youtube|spotify|local|downloaded), bitrate, albumId`.
- `id` YouTube-трека = videoId; Spotify-трека = `sp:<spotifyId>`; локального — генерируется при импорте.
- Исполнители в `artist` хранятся строкой через запятую; «основной» = первый (`track_groups.dart`).

**Hive-боксы**: `tracks`, `playlists`, `lyrics` (LRC-текст по trackId) — в `LibraryRepository`; `settings` — в `Settings`. Лайки — список id в боксе `tracks` под ключом `#liked`; `playCounts`, `recentIds`, `searchQueries` — в `settings`.

**Settings-ключи**: `workerUrl, useWorkerProxy(false), httpProxy, audioCache(false), pipedInstances, invidiousInstances, spotifyClientId/Secret(необязательны), bitrate, preferOpus, proxyAudioStreams(false), crossfadeSeconds, shuffleEnabled, repeatIndex, lastTrackId, lastPositionMs, playbackSpeed, lyricsOffsetMs(trackId)`.

**Файлы** (`StorageService`): локальные треки, обложки, `.lrc`, загрузки (`.m4a/.opus`) в каталоге приложения; `clearCache()` чистит кэш скачанного.

## 4. Сеть и обход блокировок (без настроек пользователя)

Пользовательских полей для Piped/Invidious/Worker/прокси/токенов в UI больше нет; ключи `Settings` сохранены только для совместимости.
- `YouTubeMusicClient` опрашивает **параллельно** (`firstNonEmpty`, `core/utils/async_utils.dart`): InnerTube (`InnerTubeClient`: поиск WEB_REMIX `music.youtube.com`, потоки клиентами ANDROID_VR и ANDROID без PO-токена, UA/заголовки привязаны к клиенту через `StreamCandidate.headers`), Piped, Invidious.
- Зеркала: `InstanceDirectory` раз в 24 ч сам обновляет списки из публичных каталогов (piped-instances.kavin.rocks, api.invidious.io), кэш в Hive, объединяет со встроенными. `MirrorManager.get` — волны по 3 зеркала параллельно с отменой; недоступные «остывают»; Worker (если задан старым `workerUrl`) — последний рубеж.
- Версии клиентов InnerTube — `AppConfig.androidVrVersion/androidSdklessVersion/ytMusicClientVersion`: при отказе YouTube обновить значения.
- Spotify: ссылки/запросы сопоставляются с YouTube (`pickBestMatch`), соответствие запоминается в `Settings.matchedVideo/rememberMatch`.
- Качество: `AudioQuality{low=64,medium=128,high=max,auto}`, `rankFormats` (`core/utils/audio_pick.dart`); `auto` = high по Wi‑Fi (`isOnWifi`), иначе 128; на iOS только AAC.

**Worker (встроенный):** `worker.js` + `wrangler.toml` деплоятся job'ом `worker` в `build_release.yml` при наличии секретов `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`; полученный `*.workers.dev` URL передаётся в сборку как `--dart-define=WORKER_URL` (`AppConfig.defaultWorkerUrl`). Клиент добавляет `/stream` Worker'а последним кандидатом (`WorkerHealth` — circuit breaker). Без секретов приложение работает без Worker.

**Источники:** `MusicSource` (YouTube Music / Spotify, `app/source_provider.dart`, хранится в `Settings.musicSourceIndex`) — раздельные вкладки на Главной и в Поиске; Spotify даёт метаданные, воспроизведение — через сопоставление с YouTube.

## 5. Воспроизведение (сквозной сценарий)

1. UI вызывает `audioHandler.playTrack(track, contextQueue:)` / `setLibraryQueue(...)`.
2. `_prepare()` собирает источники **лениво**: сетевой трек = `ResolvedStreamSource` (`StreamAudioSource`), URL запрашивается в момент воспроизведения через `YouTubeMusicClient.resolveCandidates` (кэш 25 мин). Сохранённые `streamUrl` не используются — они протухают (причина прежнего «Download required»).
3. `ResolvedStreamSource.request` по Range-запросам Dio пробует кандидатов по кругу, 2 раунда (второй — `fresh`, все провайдеры); заголовки — под выдавший клиент.
4. `_load()` сразу запускает `play()`, таймаут 30 с; ошибка → `_recoverFromError` → один повтор со свежими ссылками (`_retryWithFreshLinks`) → следующий трек. Буферизация — `AudioLoadConfiguration`.
5. Gapless = прогрев следующего трека (`_warmNext`, флаг `gaplessEnabled`); кроссфейд — `_fadeLevel`; нормализация — `loudnessDb` → `loudnessGain` (`normalizeVolume`, `refreshNormalization()`).
6. Загрузка: `DownloadService.download` → `resolveCandidates(fresh)` → файл + обложка + `.lrc`.

## 6. Тексты

`LyricsClient` (LRCLIB) → `StorageService.fetchLyricsFromLrclib` → `LibraryRepository.saveLyrics` → `LrcParser.parse` → `Lyrics{lines[time,text], synced, indexAt()}`. Экран `lyrics_screen.dart`: фон `AuroraBackground` (цвет обложки через `PaletteGenerator`), активная строка заливается по времени, соседние строки гаснут по прозрачности (без blur), фон — статичный тёмный градиент с ограниченной яркостью (белый текст читается в любой теме), тап — `seek`; сдвиг синхронизации хранится по треку (`lyricsOffsetMs`).

## 7. UI

Вкладки в `AppShell` (IndexedStack): Главная, Поиск, Медиатека, Создать; настройки — отдельный экран (`SettingsScreen`), открывается из Главной, Медиатеки и «Создать». Тема: `AppPalette` (dark/light, акцент, AMOLED, градиент) + статические геттеры `AppColors` (читают `AppPalette.current`); `ThemeController` (`lib/app/theme_controller.dart`) хранит выбор в `Settings`, `TrollMusicApp` выставляет палитру и после смены глубоко пересобирает дерево. Поверхности сплошные (`surface #121212`, `surfaceAlt #1E1E1E`, прозрачность 0.9–0.95, рамка 1 px `outline`), без blur/«стекла». Главная: `_DailyPick`, `_TrendingSection` («Популярная музыка», только музыка), `_Recent`, `MoodSection` (`music_sections.dart`: подборки настроений/жанров → `MoodScreen`), `_Stations`, `_Discoveries`. Настройки: Качество звука, Тема, Воспроизведение, Кэш и хранилище. Плейлист — `ReorderableListView` (порядок сохраняется). Экран артиста строится по `groupTracksByArtist`.

## 8. CI и релизы

`push` в `main` (кроме README) → jobs `Version` → `Android APK` + `iOS IPA (unsigned)` → `Publish` (ветка `releases` + GitHub Release). Версия `1.0.<run_number−1>+<run_number>`. Flutter зафиксирован в `FLUTTER_VERSION`. Тесты в CI **не запускаются** (проверять `flutter test` нужно локально).

## 9. Как вносить изменения

- Логику (парсинг, сопоставление, форматирование) выносить в `core/utils` как чистые функции + тест в `test/`.
- Новая настройка: геттер/сеттер в `Settings` → UI в `settings_screen.dart` (`_TextFieldTile`/`SwitchListTile`) → использовать через `ref.read(settingsProvider)`.
- Новый сетевой клиент: класс в `core/network/...`, URL строить через `ProxyConfig`, запросы к зеркалам — через `MirrorManager`.
- Правка структуры/провайдеров/потока воспроизведения → обновить этот файл.
- Строки UI — на русском. Не ломать существующие тесты.

## 10. Известные ограничения и риски

- Ручная проверка на устройстве (воспроизведение, экран блокировки, загрузки, бэкап, таймер сна, кроссфейд) **не проводилась** — только CI-сборка.
- Соответствие Spotify→YouTube хранится в памяти (после перезапуска ищется заново); неверный матч возможен для редких треков.
- `LockCachingAudioSource` и работа аудио через HTTP-прокси не проверены на устройстве.
- Публичные Piped/Invidious нестабильны; без собственного Worker/прокси в РФ часть зеркал может быть недоступна.
- Нет входа в аккаунт Spotify (личные плейлисты/библиотека недоступны), поиск Spotify работает только с ключами.
- Акцентный цвет и прозрачность «стекла» не настраиваются.
- `positionStream` just_audio идёт с шагом ~200 мс — подсветка текста интерполируется анимацией.
