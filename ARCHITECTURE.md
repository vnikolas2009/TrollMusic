# TrollMusic — архитектура

Flutter-приложение (iOS/Android). Состояние — Riverpod, хранилище — Hive, звук — just_audio + audio_service. Работает в РФ без VPN и без платных сервисов.

Схема:

- **Метаданные Spotify** (плейлист, альбом, трек: название, исполнитель, длительность, обложка) отдаёт собственный бесплатный Vercel-бэкенд `/api`. Аудио через Vercel **никогда** не проходит.
- **Аудио** приложение получает напрямую с CDN: сначала SoundCloud (MP3/HLS), при неудаче YouTube через InnerTube (`ANDROID_VR`/`IOS`).
- **DNS** для всех запросов Dio идёт через DNS-over-HTTPS (8.8.8.8 / 9.9.9.9), поэтому подмена DNS у провайдера не мешает.
- Тексты — LRCLIB.

Проверка: `flutter pub get`, `flutter analyze`, `flutter test` выполняются локально. CI (`.github/workflows/build_release.yml`) только собирает APK/IPA и тесты не запускает.

## 1. Слои и карта файлов

```
api/                           # Vercel serverless (TypeScript)
  _lib/spotify.ts              # анонимный токен open.spotify.com + разбор ответов Spotify
  spotify/token.ts             # GET  /api/spotify/token  → {accessToken, expiresAt}
  spotify/import.ts            # GET  /api/spotify/import?url=… → {type,id,title,cover,tracks[]}
vercel.json, package.json, tsconfig.json
lib/
  main.dart                    # ручная сборка зависимостей → ProviderContainer (overrides) → runApp
  app/
    app.dart, app_shell.dart   # MaterialApp, IndexedStack вкладок + MiniPlayer
    providers.dart             # AppServices, провайдеры библиотеки/плеера (positionProvider и др.)
    network_providers.dart     # dio, settings, SoundCloud/InnerTube/AudioResolver, Spotify, MusicRepository
  core/
    config/app_config.dart     # API base, таймауты, DoH-эндпоинты, TTL client_id, prefetch, cacheWidth
    network/
      doh_resolver.dart        # DohResolver: HttpClient.connectionFactory + DoH по IP-адресам
      http_client.dart         # createDio(): DoH + HTTP-прокси + пользовательские заголовки
      soundcloud/soundcloud_service.dart   # client_id (Hive, 24 ч), поиск, прямой MP3/HLS
      youtube/innertube_service.dart       # поиск и аудио через ANDROID_VR / IOS
      spotify/spotify_client.dart          # Vercel import/token → прямой API → embed
      lyrics/lyrics_client.dart            # LRCLIB
    storage/settings.dart      # Hive-box 'settings'
    theme/, utils/             # чистые функции (lrc_parser, track_match, spotify_link, json_isolate, …)
  data/
    models/{track,playlist,lyrics,artist}.dart
    repositories/library_repository.dart   # Hive: треки, плейлисты, лайки, тексты, бэкап
    repositories/music_repository.dart     # поиск, импорт Spotify-ссылок, тексты
  services/
    audio/audio_resolver_service.dart      # SoundCloud → InnerTube
    audio/audio_handler.dart               # TrollAudioHandler: очередь, prefetch, кроссфейд, таймер сна
    download/download_service.dart         # офлайн-загрузки
    storage/                               # файлы, импорт, теги
  features/                    # home, search, library, playlist, artist, player, lyrics, create, settings
  shared/widgets/              # track_tile, mini_player, cover_art, …
test/                          # flutter test
```

Правило слоёв: `features/shared` → `app` (провайдеры) → `services/data` → `core`. `core/utils` не зависит от Flutter-UI и Riverpod.

## 2. Инициализация и DI

`main.dart` создаёт объекты вручную и передаёт их в `ProviderContainer(overrides: ...)`:

`Hive.initFlutter → Settings.open → открытие box SoundCloud-кэша → LibraryRepository.open → SoundCloudService / InnerTubeService → AudioResolverService → StorageService → DownloadService → AudioService.init(TrollAudioHandler) → restoreLastPlayed`.

Провайдеры с `throw UnimplementedError()` (`servicesProvider`, `settingsProvider`, …) обязательно переопределяются в `main`. Остальные сетевые провайдеры строятся лениво в `network_providers.dart`.

## 3. Данные

**Track** (`data/models/track.dart`): `id, title, artist, album, duration, thumbnailUrl, streamUrl, localPath, lyricsPath, artworkPath, explicit, source (youtube|spotify|soundcloud|local|downloaded), bitrate, albumId`.
- `id` YouTube-трека = videoId; Spotify = `sp:<id>`; SoundCloud = `sc:<id>`.
- Исполнители в `artist` хранятся строкой через запятую; основной — первый.

**Hive-боксы**: `tracks`, `playlists`, `lyrics` (`LibraryRepository`), `settings` (`Settings`), `soundcloud_cache` (`client_id` + время получения).

**Settings**: `apiBaseUrl`, `httpProxy`, `useSystemProxy`, `customHeaders`, `spotifyGuestMode`, `spotifyClientId/Secret`, `bitrate`, `preferOpus`, `crossfadeSeconds`, `shuffleEnabled`, `repeatIndex`, `lastTrackId`, `lastPositionMs`, `playbackSpeed`, `lyricsOffsetMs(trackId)`, `playCounts`, `recentIds`, `searchQueries`.

## 4. Сеть

- **Dio** (`createDio`) использует `DohResolver`: имя хоста резолвится через DoH-запросы к IP-адресам (`https://8.8.8.8/resolve`, `https://9.9.9.9:5053/dns-query`), TLS проверяется по исходному имени хоста. Если DoH недоступен, используется системный DNS.
- **HTTP-прокси** (`httpProxy` или системный) необязателен. SOCKS не поддерживается.
- **Тяжёлый JSON** (ответы поиска, плеера, страницы SoundCloud) разбирается через `Isolate.run()` (`core/utils/json_isolate.dart`).
- **Vercel**: базовый URL — `AppConfig.defaultApiBase` (`--dart-define=TROLL_API_BASE=…`) или поле в настройках. Функции: `token.ts` (токен кэшируется в памяти инстанса до истечения), `import.ts` (только метаданные).

### SoundCloud (`SoundCloudService`)
1. `client_id` скрейпится со скриптов страницы soundcloud.com, хранится в Hive 24 часа; если скрейп не удался, используется просроченный id из кэша. Принудительное обновление при 401 не реализовано.
2. Поиск: `api-v2.soundcloud.com/search/tracks`.
3. Поток: `media.transcodings` → progressive MP3 предпочтительнее HLS; треки с `policy: BLOCK`/`SNIP` пропускаются.

### InnerTube (`InnerTubeService`, фолбэк)
Поиск и `player` с контекстами `ANDROID_VR` и `IOS`: прямые ссылки googlevideo без подписи и PO-токена. Для воспроизведения нужны заголовки клиента (`AudioResolverService.streamHeaders`).

### Единый резолвер (`AudioResolverService`)
Поиск и получение потока: SoundCloud первым, InnerTube при ошибке или пустом результате. Для Spotify-трека ищется кандидат по «артист название», выбирается `pickBest` (длительность, название, исполнитель, штраф за live/remix).

## 5. Воспроизведение

1. UI вызывает `audioHandler.playTrack(track, contextQueue:)` / `setLibraryQueue(...)`.
2. В очереди неразрешённые треки представлены `SilenceAudioSource`. Сразу резолвится только якорный трек.
3. При переходе на трек без URL он резолвится на месте (`_activateIfUnresolved`).
4. **Prefetch**: за 15 секунд до конца (`AppConfig.prefetchBefore`) резолвится следующий трек и подменяется в очереди (`removeAudioSourceAt` + `insertAudioSource`).
5. Сетевые не-HLS URL играются через `LockCachingAudioSource` (кэш на диск), HLS — через `AudioSource.uri`. Заголовки: `streamHeaders(url)` + `settings.requestHeaders`.
6. Ошибка потока → `errors` stream → повторный резолв → следующий трек.
7. Загрузка: `DownloadService.download(track)` → кандидаты `AudioResolverService` (HLS пропускаются) → файл + обложка + `.lrc`.

## 6. Тексты

`LyricsClient` (LRCLIB) → `LibraryRepository.saveLyrics` → `LrcParser.parse`. Экран `lyrics_screen.dart`: список перестраивается только при смене активной строки (`positionStream.map(indexAt).distinct()`); тики позиции слушает лишь прогресс активной строки; каждая строка в `RepaintBoundary`.

## 7. UI и производительность

- Позиция (`positionProvider`) слушается только узкими виджетами: `_SeekBar` в `player_screen.dart` и `_MiniProgress` в `mini_player.dart`.
- Все обложки задают `cacheWidth` (`AppConfig.coverCacheWidth` = 600 для плеера, `thumbCacheWidth` = 160 для плиток, `CoverArt` считает от размера и devicePixelRatio).
- Вкладки в `AppShell` (IndexedStack). Палитра `AppColors`, акцент #1ED760.

## 8. Деплой бэкенда

```bash
npm i -g vercel
vercel --prod
```

Переменные окружения не нужны. Полученный домен укажите в `AppConfig.defaultApiBase` (или `--dart-define=TROLL_API_BASE=…`, либо в настройках приложения).

## 9. CI и релизы

`push` в `main` → `Version` → `Android APK` + `iOS IPA (unsigned)` → `Publish` (ветка `releases` + GitHub Release). Версия `1.0.<run_number−1>+<run_number>`. Тесты в CI не запускаются.

## 10. Как вносить изменения

- Логику (парсинг, сопоставление, форматирование) выносить в чистые функции и покрывать тестом в `test/`.
- Новая настройка: геттер/сеттер в `Settings` → UI в `settings_screen.dart`.
- Новый источник аудио: сервис в `core/network/...`, подключение в `AudioResolverService`. Аудио не проксировать через Vercel.
- Правка структуры, провайдеров, потока воспроизведения или сети → обновить этот файл.
- Строки UI — на русском. Существующие тесты не ломать.

## 11. Известные ограничения

- Ручная проверка на устройстве (воспроизведение, экран блокировки, загрузки, кроссфейд, prefetch) не проводилась.
- `LockCachingAudioSource` в just_audio помечен как экспериментальный.
- Приватные API (`client_id` SoundCloud, клиенты InnerTube) могут меняться без предупреждения. Версии клиентов InnerTube заданы константами в `innertube_service.dart`.
- Соответствие Spotify → SoundCloud/YouTube хранится в памяти; для редких треков возможен неверный матч.
- Нет входа в аккаунт Spotify: личные плейлисты недоступны.
- Бесплатный тариф Vercel ограничивает число вызовов; аудио через него не идёт.
