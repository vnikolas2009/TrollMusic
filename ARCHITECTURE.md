TrollMusic — архитектура и инструкции для AI-агентов

Этот документ помогает Claude Code / Claude Sonnet ориентироваться в
репозитории. Это карта проекта, а не источник истины: если описание
расходится с кодом текущей ветки, проверяй исходники, вызовы и тесты,
затем обновляй документ.

Инструкции агенту

Перед работой: 1. Прочитай README.md и этот файл. 2. Проверь
актуальную структуру и содержимое файлов в текущей ветке. Не полагайся
на старые чаты. 3. Найди все usages изменяемых классов, методов, моделей
и providers. 4. Проследи поток данных: UI → provider/repository →
service → network/storage → UI. 5. Делай минимальные изменения. Не
переписывай несвязанные файлы. 6. Не выдумывай API, методы и
зависимости: сверяйся с pubspec.yaml и pubspec.lock. 7. Сохраняй
совместимость существующих данных Hive/JSON. 8. Не помещай токены,
cookies, пароли и ключи в код, логи или репозиторий. 9. Не обходи
авторизацию, paywall и ограничения доступа. Используй разрешённые
API/OAuth. 10. Не утверждай, что тесты прошли, если они реально не
запускались. 11. Не делай force-push и не меняй main для рискованных
задач без прямого указания. 12. В отчёте перечисли изменённые файлы,
проверки и оставшиеся риски.

Источники музыки (добавлено)

Сервисы: core/network/yandex/yandex_music_service.dart (префикс id
`ym:`), core/network/vk/vk_music_service.dart (`vk:`),
core/network/audius/audius_service.dart (`au:`). Парсеры вынесены в
чистые функции и покрыты test/new_sources_test.dart. Резолвер
(`AudioResolverService`) сначала пробует родной источник трека
(`_resolveNative`), затем SoundCloud/YouTube. Токены Яндекса и VK
вводит пользователь (Settings.yandexToken / vkToken, провайдер
serviceTokensProvider); в коде и репозитории токенов нет. Без токена
VK недоступен, Яндекс отдаёт только метаданные. Переключатель
источника: MusicSource (порядок значений менять нельзя, в Hive хранится
индекс) и shared/widgets/source_switcher.dart.

UI-заметки: AppColors.appBarBackground делает SliverAppBar прозрачным,
пока контент не под ним (иначе чёрная плашка закрывает градиент).
Ползунок плеера: shared/widgets/scrubber.dart + core/utils/seek_math.dart;
позицию слушает только _SeekBar.

Анимации на пружинах (DesignBookmark)

core/motion/spring.dart: Spring (полунеявный Эйлер, 4 подшага, dt не
больше 1/30 с), SpringLoop (Ticker) и SpringTokens (значения из
tokens.css). core/motion/rubber.dart: резиновое сопротивление.
core/utils/read_along.dart: деление строки на слова и индекс слова по
доле строки. Виджеты: shared/widgets/read_along_text.dart (используется
в lyrics_screen для активной строки), spring_switch.dart и
rubber_dock.dart. Rubber dock — нижняя навигация в app_shell.dart (5 вкладок: Главная, Поиск, Медиатека, Создать, Настройки; TrollBottomNav удалён), spring_switch — переключатели в настройках. Оболочка: Column(IndexedStack вкладок, MiniPlayer, RubberDock) — мини-плеер над доком на всех вкладках. Тесты: test/motion_test.dart, test/tab_provider_test.dart.

1. Проект

TrollMusic — Flutter-приложение для iOS и Android.

Область            Технология

────────

UI / язык          Flutter, Dart
Состояние          Riverpod (flutter_riverpod)
HTTP               Dio
YouTube            youtube_explode_dart
Плеер              just_audio, audio_service, audio_session
Локальные данные   Hive / hive_flutter
Spotify            получение метаданных; аудио ищется на других источниках
Тексты             LRCLIB
Backend            Vercel Serverless Functions (TypeScript)
CI                 GitHub Actions

2. Карта репозитория

lib/
├── main.dart                         # Инициализация Flutter и DI
├── app/
│   ├── app.dart, app_shell.dart      # MaterialApp и оболочка
│   ├── providers.dart                # Библиотека, плеер, загрузки, UI streams
│   ├── network_providers.dart        # Dio, сетевые сервисы, repositories
│   ├── tab_provider.dart              # Текущая вкладка дока (selectedTabProvider, AppTab)
│   ├── source_provider.dart           # Выбранный источник каталога
│   └── theme_controller.dart
├── core/
│   ├── config/app_config.dart         # URL, timeout, TTL, общие параметры
│   ├── network/
│   │   ├── doh_resolver.dart          # DNS-over-HTTPS
│   │   ├── http_client.dart           # createDio(), proxy, HTTP adapter
│   │   ├── soundcloud/soundcloud_service.dart
│   │   ├── youtube/innertube_service.dart
│   │   ├── spotify/spotify_client.dart
│   │   └── lyrics/lyrics_client.dart
│   ├── storage/settings.dart          # Hive-настройки
│   └── utils/                         # Парсеры и чистые функции
├── data/
│   ├── models/                        # Track, Playlist, Lyrics, Artist
│   └── repositories/
│       ├── library_repository.dart    # Hive: tracks/playlists/lyrics
│       └── music_repository.dart      # Поиск, подборки, Spotify, lyrics
├── services/
│   ├── audio/
│   │   ├── audio_handler.dart         # Очередь и воспроизведение
│   │   └── audio_resolver_service.dart# Поиск аудиопотоков и fallback
│   ├── download/download_service.dart
│   └── storage/                       # Файлы, импорт, теги
├── features/                          # home, search, library, playlist,
│                                      # artist, player, lyrics, create, settings
└── shared/widgets/                    # Общие UI-компоненты

api/
├── _lib/spotify.ts
└── spotify/
    ├── token.ts
    └── import.ts

test/                                  # flutter_test
.github/workflows/build_release.yml   # APK + unsigned IPA + публикация
pubspec.yaml                           # Зависимости и SDK

Это главные точки входа, а не полный список. Перед созданием файлов
проверь актуальное дерево.

3. Слои и направление зависимостей

features / shared widgets
          ↓
      app/providers
          ↓
 repositories / services
       ↙       ↘
    data       core
              (network, config,
               storage, utils)

• features/ — экраны и пользовательские сценарии; не размещай
здесь HTTP-клиенты.
• app/ — composition root для Riverpod и зависимости приложения.
• data/repositories/ — координация получения и хранения данных.
• services/ — прикладная логика аудио, загрузок и файлов.
• core/ — сеть, конфигурация, настройки и утилиты.
• data/models/ — модели без зависимости от UI.

Не создавай повторные экземпляры сервисов без причины: это может
разделить кэш и сетевые настройки.

4. Инициализация и DI

Точка входа — lib/main.dart. Текущая последовательность: 1.
Инициализация Flutter и Hive. 2. Открытие Settings, SoundCloud cache box
и LibraryRepository. 3. Создание LyricsClient, SoundCloudService,
InnerTubeService и AudioResolverService. 4. Создание StorageService и
DownloadService. 5. Инициализация AudioService с TrollAudioHandler и
восстановление последнего трека. 6. Создание ProviderContainer с
overrides и запуск TrollMusicApp.

lib/app/network_providers.dart связывает Dio, Settings, SoundCloud,
InnerTube, AudioResolver, Spotify, Lyrics и MusicRepository.

lib/app/providers.dart предоставляет AppServices, LibraryRepository,
StorageService, DownloadService, AudioHandler и UI stream providers.

Некоторые providers намеренно выбрасывают UnimplementedError() и
переопределяются в main.dart (например, settingsProvider,
servicesProvider). Не удаляй overrides, не проверив usages.

5. Track и локальное хранилище

Модель: lib/data/models/track.dart.

Поля включают ID, title, artist, album, duration, thumbnailUrl,
streamUrl, localPath, lyricsPath, artworkPath, explicit, source, bitrate
и albumId.

Текущий enum:

enum TrackSource { youtube, spotify, soundcloud, local, downloaded }

Текущие ID: - YouTube: video ID; - Spotify: sp:<id>; - SoundCloud:
sc:<id>; - local/downloaded: проверь места создания треков.

При добавлении источника: 1. Проверь все switch/if по TrackSource. 2.
Определи уникальный стабильный ID prefix. 3. Проверь
Track.toJson/fromJson и чтение старых записей. 4. Проверь library,
playlists, likes, queue, import/export, downloads и UI. 5. Добавь тесты
сериализации и старых данных.

Важно: текущий Track.copyWith использует ??; передача null не
очищает nullable-поле. Не меняй это поведение без проверки всех вызовов.

Hive boxes: - tracks, playlists, lyrics — LibraryRepository; -
settings — Settings; - soundcloud_cache — SoundCloud client_id
cache.

Не меняй имена boxes/ключей без миграции или совместимого fallback.

6. Поиск и источники аудио

MusicRepository

lib/data/repositories/music_repository.dart: - searchAll()
параллельно вызывает SoundCloud, YouTube и Spotify; удаляет дубли по
source + ID. - searchSpotify() сначала ищет Spotify, затем использует
YouTube как fallback. - youtubeMix() и spotifyMix() собирают
подборки из нескольких запросов. - spotifyPlaylist() разбирает
Spotify-ссылку и импортирует playlist/album. - findLyrics() обращается
к LyricsClient.

SoundCloudService

lib/core/network/soundcloud/soundcloud_service.dart: - получает
client_id со страницы SoundCloud и JS-бандлов; - хранит client_id в Hive
с TTL из AppConfig; - при 401/403 обновляет client_id и повторяет
запрос; - ищет треки через SoundCloud API; - получает транскодинги;
progressive обычно предпочтительнее HLS; - кэширует stream URLs с
ограниченным TTL.

При изменениях проверяй 401/403, retry, пустые транскодинги, BLOCK/SNIP
policy, HTTPS и истечение URL.

YouTube / InnerTubeService

Файл: lib/core/network/youtube/innertube_service.dart.

Название историческое: текущая реализация поиска и получения потоков
использует youtube_explode_dart, а не самописный низкоуровневый
InnerTube-клиент. Поиск идёт через YouTube search; stream manifest
запрашивается с клиентами Safari и Android VR. Форматы сортируются по
кодеку и bitrate, URL кэшируются временно.

В файле также оставлены legacy parsing helpers для совместимости с
тестами. Не удаляй их без проверки тестов и usages.

AudioResolverService

lib/services/audio/audio_resolver_service.dart — единая точка
получения кандидатов: - существующий streamUrl используется первым; -
YouTube source: YouTube → SoundCloud; - остальные sources: SoundCloud →
YouTube; - для Spotify metadata подбирается аудиокандидат поиском и
pickBestMatch; - найденные URL кэшируются в памяти; - forget()
очищает кэш резолвера и кэши источников.

Заголовки прямого YouTube-потока определяются через streamHeaders().
Не удаляй их без проверки на iOS/Android.

Как добавить новый источник

Не подключай API прямо в экран или AudioHandler: 1. Изучи Track,
AudioResolverService, MusicRepository, DownloadService и
TrollAudioHandler. 2. Создай отдельный network service в
lib/core/network/<source>/. 3. Используй общий
createDio(settings: ...), если он подходит протоколу. 4. Добавь
provider и DI в main.dart, если нужен единый жизненный цикл. 5. Раздели
каталог метаданных и получение реального аудио: это разные возможности.
6. Определи ID, enum source, приоритет, headers, timeout, retry, TTL и
cache invalidation. 7. Подключи поиск и резолвинг в orchestration
layers. 8. Проверь playback, очередь, prefetch, downloads, offline,
import/export. 9. Добавь тесты парсинга, matching, ошибок и пустых
ответов.

Не предполагай, что наличие поиска означает возможность потокового
воспроизведения. Не используй приватные API/учётные данные способом,
нарушающим правила сервиса.

7. Воспроизведение и загрузки

TrollAudioHandler

lib/services/audio/audio_handler.dart отвечает за очередь, MediaItem,
play/pause/seek, shuffle/repeat, crossfade, скорость, восстановление
позиции, prefetch и ошибки.

Особенности текущего кода: - неразрешённые элементы очереди могут
временно быть SilenceAudioSource; - удалённые non-HLS URL
воспроизводятся через LockCachingAudioSource; - HLS (.m3u8) передаётся
через AudioSource.uri; - локальные файлы воспроизводятся напрямую; -
AudioHandler вызывает resolver для подготовки и повторного получения
URL.

Изменения очереди/AudioPlayer могут затронуть экран блокировки, кнопки
гарнитуры, переходы, восстановление состояния и prefetch.

DownloadService

lib/services/download/download_service.dart: - сначала пробует
известный streamUrl, затем кандидаты resolver; - пропускает HLS при
скачивании; - поддерживает ограниченную параллельность, прогресс и
отмену; - сохраняет аудио, обложку и при возможности текст; - обновляет
Track в LibraryRepository.

При изменении headers/URL проверяй playback и download: пути используют
общую инфраструктуру, но не идентичны.

8. Сеть и конфигурация

lib/core/config/app_config.dart содержит API base URL, timeout, DoH
endpoints, SoundCloud TTL, prefetch duration, image cache widths,
default headers и параметры YouTube-клиентов. Не дублируй эти значения
без необходимости.

Файлы HTTP/DNS: - lib/core/network/http_client.dart -
lib/core/network/doh_resolver.dart

createDio() централизует Dio options, таймауты, заголовки, HTTP
adapter и DNS resolver. Приоритет proxy: ручной HTTP → системный →
прямое соединение. Не считай SOCKS поддержанным без отдельной
реализации.

При изменении сети проверь TLS hostname verification, DNS fallback,
proxy, timeout и ошибки. Не отключай TLS validation ради обхода сетевых
проблем.

9. Spotify и Vercel API

lib/core/network/spotify/spotify_client.dart отвечает за Spotify
metadata/search/track/album/playlist. Он не отдаёт прямые аудиопотоки
Spotify. Воспроизведение Spotify-трека выполняется через поиск
подходящего аудио на других источниках.

Backend:

api/_lib/spotify.ts
api/spotify/token.ts
api/spotify/import.ts

Маршруты: - GET /api/spotify/token — анонимный web token; -
GET /api/spotify/import?type=playlist&id=<id> — metadata playlist; -
GET /api/spotify/import?type=album&id=<id> — metadata album; -
GET /api/spotify/import?type=track&id=<id> — metadata track.

Важно: текущий import endpoint принимает type и id, а не url. Не
используй устаревший /api/spotify/import?url=....

Аудио через Vercel не проксируется. При изменении API синхронно проверь
TypeScript handlers, Flutter client, README и Vercel config.

10. Lyrics и UI

Lyrics: - client: lib/core/network/lyrics/lyrics_client.dart; -
источник: LRCLIB; - parser: lib/core/utils/lrc_parser.dart; - storage:
LibraryRepository / Hive box lyrics; - screen:
lib/features/lyrics/lyrics_screen.dart.

Сохраняй различие synced LRC и plain text. Проверяй timestamps,
malformed lines, пустые ответы и seek-to-line.

UI находится в lib/features/, общие элементы — в
lib/shared/widgets/. Не дублируй существующие widgets и не переноси
бизнес-логику в UI. Частые position updates должны перестраивать только
необходимые небольшие виджеты. Учитывай cacheWidth обложек.

11. Проверки и CI

Запускать из корня:

flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

Точечные проверки:

dart format --output=none --set-exit-if-changed lib/path/to/file.dart
flutter test test/name_of_test.dart

--output=none только проверяет форматирование, не изменяет файлы.

.github/workflows/build_release.yml собирает Android APK и iOS IPA без
codesign, затем публикует их в ветку releases и GitHub Release.
Текущий release workflow не запускает flutter analyze и
flutter test. Не утверждай, что CI проверил тесты, если отдельный
workflow не добавлен и не запускался.

12. Чек-лист завершения

☐ Найдены все usages изменённого API и модели.
☐ Сохранена совместимость старых Hive/JSON данных.
☐ Проверены пустые ответы, ошибки, timeout, retry и cache
invalidation.
☐ Проверены iOS/Android особенности при изменении сети или аудио.
☐ Проверены очередь, prefetch, экран блокировки при изменении
playback.
☐ Проверены загрузки и offline при изменении источника.
☐ Добавлены/обновлены тесты.
☐ Реально выполнены format/analyze/test или описано, почему это
невозможно.
☐ Обновлены README/ARCHITECTURE при изменении архитектуры.

13. Известные риски

• Внешние API SoundCloud/YouTube/Spotify и их ответы могут меняться.
• Ссылки на аудиопотоки могут истекать.
• Spotify metadata matching может выбрать live/remix/cover вместо
оригинала.
• LockCachingAudioSource помечен в just_audio как experimental.
• Unsigned IPA не означает, что приложение подписано и готово к
обычной установке.
• Успешная сборка не заменяет ручную проверку воспроизведения на iOS и
Android.

────────

Последнее сверение структуры: ветка main. После существенных
архитектурных изменений обновляй этот документ.

Сеть: DohResolver опрашивает DoH-серверы параллельно (A и AAAA независимы), IPv4 идёт первым; connect() реально перебирает адреса с таймаутом и при неудаче берёт системный DNS. Главная для Spotify при недоступном Spotify показывает подборку YouTube Music.

Оформление: shared/widgets/brand_wordmark.dart (надпись), aurora_background.dart (фон под вкладками в app_shell.dart), tool/gen_icon.py (иконки).
