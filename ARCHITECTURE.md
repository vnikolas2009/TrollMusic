# Архитектура TrollMusic

Flutter-приложение: только локальные файлы. Сеть используется для одного: поиск текстов песен (LRCLIB, NetEase, Kugou, QQ Music, Lyrics.ovh). Бэкенда нет.

## Карта файлов

```
lib/
  main.dart                      инициализация Hive, audio_service, DI, стартовые задачи
  app/
    app.dart, app_shell.dart     MaterialApp, нижний док (5 вкладок), мини-плеер
    providers.dart               Riverpod: библиотека, хранилище, импорт, плеер, текущий трек
    settings_provider.dart       settingsProvider, lyricsServiceProvider
    lyrics_job.dart              пакетный поиск текстов (3 параллельных запроса, отмена)
    tab_provider.dart, theme_controller.dart
    lyrics_style_provider.dart   стиль текстов песен (spotify / minimal / classic), хранится в настройках
  core/
    config/app_config.dart       расширения файлов, таймауты, user-agent
    network/http_client.dart     createDio() для запросов текстов
    network/lyrics/lyrics_providers.dart   LRCLIB, NetEase (+ yrc → enhanced LRC), Lyrics.ovh
    storage/settings.dart        настройки и история прослушивания (Hive)
    utils/lrc_parser.dart        разбор/запись LRC и enhanced LRC, plainLines для текста без таймкодов
    utils/lyric_style.dart       LyricsStyle: вид строк и яркость по расстоянию до текущей
    utils/lyrics_match.dart      чистка названий, варианты запросов, выбор кандидата, сопоставление .lrc с треком
    utils/track_sort.dart        сортировка, группировка по альбомам
    utils/track_search.dart      поиск по медиатеке и по текстам
    utils/track_groups.dart      исполнители, подборка дня
    utils/path_repair.dart       починка путей после смены контейнера iOS
  data/
    models/                      Track, Playlist, Lyrics (LyricLine, LyricWord)
    repositories/library_repository.dart   Hive: треки, плейлисты, тексты, избранное
  services/
    audio/audio_handler.dart     just_audio + audio_service: очередь, таймер сна, кроссфейд
    storage/storage_service.dart файлы приложения, импорт тегов/обложек, сохранение текста
    storage/import_service.dart  выбор файлов и папок, привязка .lrc, онлайн-поиск текста
    lyrics/lyrics_service.dart   перебор источников, выбор лучшего текста
  features/                      home, library (+track_list_screen), playlist, search, player,
                                 lyrics, create (импорт, теги, резервная копия), settings
  shared/widgets/                track_tile, track_actions (общее меню трека), cover_art, mini_player,
                                 mini_player_bar (мини-плеер для экранов поверх оболочки), tab_header
                                 (единый заголовок вкладок), rubber_dock, jelly_slider, ...
  features/player/lyric_preview  текущая строка под обложкой; нажатие → openLyricsScreen
test/                            чистая логика: LRC, сопоставление, сортировка, поиск, модели
```

## Данные

- `Track.id` вида `local:<uuid>`; файл копируется в `<support>/trollmusic/audio`, обложки в `artwork`, тексты в `lyrics`.
- Хранилище Hive: боксы `tracks`, `playlists`, `lyrics` (сырой LRC/текст по id трека), `settings`.
- Старые записи стриминговых версий читаются без ошибок (лишние ключи JSON игнорируются); записи без файла удаляются при запуске (`pruneUnplayable`).
- Путь файла на iOS меняется при переустановке: `StorageService.repairPaths` ищет файл по имени в новой папке.

## Поток импорта и текстов

1. `ImportService.pickAndImport` / `scanFolder` копируют аудио, читают теги (`audio_metadata_reader`).
2. Текст для трека берётся в порядке: `.lrc` рядом с аудио → тег файла → (после импорта, если включено) онлайн-поиск.
3. Оставшиеся `.lrc` привязываются к трекам: по имени аудиофайла, названию, «Артист - Название», тегам `[ti:]`/`[ar:]` (`lyricsFileMatchesTrack`).
4. Онлайн: `LyricsService.find` строит до трёх запросов (`buildQueries`), опрашивает источники по очереди, `pickBest` оценивает кандидатов (название, исполнитель, длительность, наличие меток; enhanced > LRC > обычный).
5. `LrcParser.parse` разбирает текст при показе; пословные метки попадают в `LyricLine.words`.

## Воспроизведение

- `TrollAudioHandler` принимает только треки с существующим файлом (`LibraryRepository.isAvailable`).
- Позицию (`positionProvider`) слушайте только в узких виджетах (`_SeekBar`, `_MiniProgress`), не в `build` экранов.
- Таймер сна «до конца трека» следит за позицией: `completed` в just_audio наступает только в конце очереди.
- Ошибка файла: `_skipBroken` включает следующий трек.

## Ограничения

- Онлайн-источники текстов неофициальные (NetEase) и могут измениться или быть недоступны в вашей сети; остальное работает офлайн.
- Пропуск тишины работает только на Android.
- Перед коммитом: `flutter pub get`, `flutter analyze`, `flutter test`.
