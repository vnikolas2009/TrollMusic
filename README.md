# YSPlayer

Кроссплатформенный музыкальный плеер (iOS / Android): матовый тёмный интерфейс, офлайн-загрузки, YouTube Music через пул зеркал Piped/Invidious, Spotify через Cloudflare Worker-прокси, тексты песен с LRCLIB.

## Возможности

- **Поиск и стриминг**: Piped + Invidious с быстрым фолбэком (таймаут 3 с), параллельное разрешение потоков, восстановление после ошибок, настраиваемый Cloudflare Worker.
- **Spotify**: API через прокси (client id/secret необязательны) либо разбор публичного embed.
- **Офлайн**: менеджер загрузок с прогрессом по байтам, отменой, удалением и лимитом параллельных задач; скачиваются `.m4a`/`.opus`, обложка и `.lrc`.
- **Локальная музыка**: импорт mp3/m4a/flac/wav/ogg/opus/aac, чтение ID3-тегов и обложки, редактор тегов, сброс обложки, поиск текста в LRCLIB, импорт `.lrc`/`.txt`, ручная вставка.
- **Плеер**: фоновая работа и экран блокировки (audio_service), управление очередью (переупорядочивание, удаление, очистка, «играть следующим»), shuffle/repeat, кроссфейд, таймер сна, скорость воспроизведения, информация о треке.
- **Тексты**: полноэкранный синхронизированный просмотр с авто-скроллом и сдвигом синхронизации, тап по строке — переход к моменту.
- **История**: недавно слушали, счётчик прослушиваний, очистка.
- **Плейлисты**: создание, переименование, удаление, добавление/удаление треков, импорт Spotify по ссылке.
- **Диагностика**: проверка доступности зеркал с задержкой, сброс кэша скачанного.
- **Резервные копии**: JSON-экспорт/импорт медиатеки.

## Стек

Flutter 3.50 · just_audio · audio_service · audio_session · dio · hive_flutter · file_picker · permission_handler · path_provider · palette_generator · audio_metadata_reader · riverpod

## Структура

```
lib/
  app/           # оболочка, провайдеры, маршрутизация
  core/          # конфиг, тема, сеть (piped/spotify/lrclib/proxy), утилиты
  data/          # модели (Track, Playlist, Lyrics), репозитории
  services/      # аудио-менеджер, загрузки, хранилище/импорт
  features/      # home, search, library, playlist, player, lyrics, create, settings
  shared/        # виджеты (обложки, станции, трек-плитки, мини-плеер)
worker.js        # Cloudflare Worker reverse proxy
```

## Worker

Задеплойте `worker.js` в Cloudflare Workers. Переменные: `PIPED_ORIGIN`, `INVIDIOUS_ORIGIN`, `ALLOWED_HOSTS`, опционально `SPOTIFY_TOKEN`.

Маршруты: `/spotify/*`, `/accounts/*`, `/cdn/*`, `/embed/*`, `/piped/*`, `/invidious/*`, `/proxy?url=...`.

В настройках приложения укажите свой Cloudflare Worker URL.

## Сборка

```bash
flutter pub get
flutter run
flutter build apk --release
```

## CI

Push в `main` собирает `YSPlayer-v<version>-android.apk` + `YSPlayer-v<version>-ios.ipa` (unsigned), публикует в ветку `releases` + GitHub Release `v<version>`.

Версия: `1.0.<run_number - 1>+<run_number>` (первый запуск — `1.0.0+1`).
