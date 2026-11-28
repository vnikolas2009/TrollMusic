# Архитектура TrollMusic

Flutter-приложение: только локальные файлы. Сеть используется для: поиска текстов песен (LRCLIB, Kugou, QQ Music, Lyrics.ovh), перевода текстов (бесплатная точка Google Translate без ключа) и встроенного браузера, из которого можно скачать аудиофайл в медиатеку. Бэкенда нет.

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
    appearance_controller.dart   косметика: толщина и размер шрифта, анимации, эффекты, форма обложек, размер текста песен
    font_controller.dart         выбранный шрифт (стандартный / импортированный), применяется в теме
  core/
    config/app_config.dart       расширения файлов, таймауты, user-agent
    network/http_client.dart     createDio() для запросов текстов
    network/lyrics/lyrics_providers.dart   LRCLIB, Lyrics.ovh (Kugou и QQ — в asia_providers.dart)
    storage/settings.dart        настройки и история прослушивания (Hive)
    utils/lrc_parser.dart        разбор/запись LRC и enhanced LRC, plainLines для текста без таймкодов
    theme/appearance.dart        AnimationMode, EffectsLevel, CoverShape и AppAppearance (читается виджетами статически)
    theme/app_fonts.dart         встроенные шрифты Inter и Manrope (assets/fonts, лицензия OFL)
    utils/loop_range.dart        LoopRange и loopRangeForLine: повтор строки текста (долгое нажатие на строку)
    utils/font_check.dart        проверка TTF/OTF (заголовок, таблицы, имя семейства) до загрузки
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
    fonts/font_service.dart      импорт шрифтов: проверка, копия в <root>/fonts, регистрация через FontLoader
    lyrics/lyrics_service.dart   перебор источников, выбор лучшего текста
  features/                      home, library (+track_list_screen), playlist, search, player,
                                 lyrics, create (импорт, теги, резервная копия), settings
  shared/widgets/                track_tile, track_actions (общее меню трека), cover_art, mini_player,
                                 mini_player_bar (мини-плеер для экранов поверх оболочки), tab_header
                                 (единый заголовок вкладок), rubber_dock, jelly_slider (+ JellyValueSlider), scale_slider_tile, ...
  features/lyrics/lyrics_backdrop      фон экрана текста: картинка/GIF под затемнением или градиентом, иначе цвет обложки (lyrics_background_provider, core/utils/lyrics_bg)
  features/browser/web_browser_screen  встроенный браузер (webview_flutter): JS-хук `play()` и перехват ссылок на аудио → предложение скачать → ImportService.importDownloaded
  services/web/web_download_service    скачивание по прямой ссылке (Dio), проверка типа ответа, имя файла
  core/utils/web_audio                 адресная строка → URL/поиск, признаки аудио, имя файла (тесты: web_audio_test)
  app/translation_provider.dart        перевод: включён ли и язык (настройки), lyricsTranslationProvider(trackId) — кэш, затем сеть
  services/lyrics/translation_service  перевод пакетами строк, кэш в <root>/translations (хэш исходных строк), исходный LRC не меняется
  core/utils/translation.dart          языки, исходные строки, пакеты, разбор ответа, выравнивание по строкам
  core/utils/smart_shuffle.dart        умное перемешивание (вес по истории, разведение исполнителей)
  core/utils/session.dart              restoreQueue/trimQueue: восстановление очереди без недоступных треков
  app/dock_provider.dart               порядок и скрытие вкладок нижней панели (dockLayoutProvider), описания вкладок
  core/utils/dock_layout.dart          normalizeDock/setTabHidden/reorderTabs: настройки скрыть нельзя, видимых ≥ 2
  features/settings/dock_settings_screen  перетаскивание и переключатели вкладок
  core/utils/track_filter.dart         lacksArtwork: фильтр «без обложек» в медиатеке (+ добавление по очереди)
  shared/widgets/confirm_dialog.dart   confirmAction: общий диалог подтверждения необратимых действий
  core/utils/sleep_fade.dart           громкость затухания таймера сна (последние 45 с; «до конца трека» — 20 с)
  core/utils/lyric_practice.dart       режим тренировки: частичное скрытие слов строки (app/lyrics_practice_provider)
  core/utils/play_stats.dart           журнал прослушиваний (Settings.playLog) → статистика за период (features/settings/stats_screen)
  shared/widgets/heart_button.dart     «Нравится» с частицами; пульс кнопки воспроизведения — в player_screen
  features/home/news_banner      синяя плашка с каналом t.me/TrollCerts (url_launcher, открывает внешнее приложение; сеть самим приложением не используется)
  features/player/lyric_preview  текущая строка под обложкой (или кнопка «Текст песни»); нажатие → openLyricsScreen (круговое раскрытие)
  features/lyrics/lyrics_settings_sheet  все настройки текста (стиль, размер, строка под обложкой); кнопка в шапке экрана текста
test/                            чистая логика: LRC, сопоставление, сортировка, поиск, модели
```

## Данные

- `Track.id` вида `local:<uuid>`; файл копируется в `<support>/trollmusic/audio`, обложки в `artwork`, тексты в `lyrics`.
- Хранилище Hive: боксы `tracks`, `playlists`, `lyrics` (сырой LRC/текст по id трека), `settings`.
- Нижняя панель: `AppShell` строит док и `IndexedStack` из видимых вкладок (`visibleDockTabs`), состояние вкладок сохраняется по `ValueKey(id)`. Номера вкладок (`AppTab`) постоянны, меняются только порядок и видимость. Если «Импорт» скрыт, пустая главная открывает его отдельным экраном.
- Переходы между экранами: `AppPageTransitionsBuilder` (въезд снизу с масштабом, нижний экран уходит вглубь); при отключённых анимациях переход мгновенный.
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
- Сессия: `queue` и индекс сохраняются в настройках (`sessionQueue`, `sessionIndex`) при любом изменении, позиция — раз в 5 с, при паузе и при уходе в фон (`flushSession` из `app.dart`). Пока трек не загружен или идёт восстановление, позиция не записывается; `restoreLastPlayed` читает её до загрузки очереди.
- `playShuffled` при включённом «умном перемешивании» готовит порядок сам (`smartShuffle`) и выключает случайный режим плеера, иначе он перемешал бы его заново.

## Ограничения

- Онлайн-источники текстов (Kugou, QQ Music) неофициальные и могут измениться или быть недоступны в вашей сети; остальное работает офлайн.
- Пропуск тишины работает только на Android.
- Перед коммитом: `flutter pub get`, `flutter analyze`, `flutter test`.
