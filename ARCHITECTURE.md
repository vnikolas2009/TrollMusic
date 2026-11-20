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

## 4. Сеть и обход блокировок

Порядок попыток (YouTube-зеркала и Spotify embed):
1. **Напрямую** (`ProxyConfig.enabled == false`, по умолчанию) — `ProxyConfig._mirror/_build` строят прямые URL.
2. **Запасной проход через Worker**, если задан `workerUrl` и прямой не сработал (`viaWorker=true`; в `MirrorManager.get` и `SpotifyClient.playlistViaEmbed`). Переключатель `useWorkerProxy` делает Worker основным путём.
3. **HTTP-прокси** `httpProxy` применяется ко всем Dart-соединениям через `HttpOverrides` (dio, `LockCachingAudioSource`). Нативный плеер (ExoPlayer/AVPlayer) прокси Dart не видит → при заданном прокси или `audioCache` сетевые URL играются через `LockCachingAudioSource` (`YsAudioHandler._source`). SOCKS не поддерживается (ограничение dart:io).

`proxyAudioStreams` оборачивает аудио-URL в `/proxy?url=` Worker'а (только если Worker задан). Публичного Worker нет — пользователь деплоит `worker.js` сам. Маршруты Worker — в README.

## 5. Воспроизведение (сквозной сценарий)

1. UI вызывает `audioHandler.playTrack(track, contextQueue:)` / `setLibraryQueue(...)`.
2. `_prepare()` для треков без `localPath/streamUrl` параллельно (до 4 воркеров, общий таймаут 8 с, «якорный» трек первым) вызывает `resolveStream(track)` = `YouTubeMusicClient.streamUrlForTrack`.
3. **Spotify-трек** (`sp:`): `streamUrlForTrack` ищет на YouTube `«артист название»`, выбирает лучший результат `pickBestMatch` (длительность ±10 с, название, исполнитель, штраф за live/remix), кэширует `spotifyId→videoId` на сессию, затем берёт поток. YouTube-трек: `Piped /streams/<id>` → фолбэк Invidious.
4. `_load()` собирает `AudioSource` (`_source`: файл/сеть/кэширующий), `setAudioSources`, кроссфейд, таймер сна, скорость, shuffle/repeat — всё внутри `YsAudioHandler`. UI читает состояние через `currentTrackProvider`/`playbackStateProvider`/`positionProvider`.
5. Ошибка потока → `errors` stream, попытка перерезолвить URL (`needsFresh`, ~стр. 460) → следующий трек.
6. Загрузка: `DownloadService.download(track)` → `streamUrlForTrack` → файл + обложка + `.lrc`; трек получает `localPath`, `source=downloaded`.

## 6. Тексты

`LyricsClient` (LRCLIB) → `StorageService.fetchLyricsFromLrclib` → `LibraryRepository.saveLyrics` → `LrcParser.parse` → `Lyrics{lines[time,text], synced, indexAt()}`. Экран `lyrics_screen.dart`: фон `AuroraBackground` (цвет обложки через `PaletteGenerator`), активная строка заливается по времени, соседние размыты (`ImageFiltered`), тап — `seek`; сдвиг синхронизации хранится по треку (`lyricsOffsetMs`).

## 7. UI

Вкладки в `AppShell` (IndexedStack): Главная, Поиск, Медиатека, Создать; настройки — отдельный экран (`SettingsScreen`), открывается из Главной, Медиатеки и «Создать». Палитра `AppColors` (#000/#121212/#181818/#282828, акцент #1ED760 — **константа**, динамической темы нет). Главная: `_DailyPick`, `_Stations`, `_Recent`, `_Discoveries`, `_TrendingSection` (тренды при пустой медиатеке). Плейлист — `ReorderableListView` (порядок сохраняется). Экран артиста строится по `groupTracksByArtist`.

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
