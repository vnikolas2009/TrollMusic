# YSPlayer

Кроссплатформенный музыкальный плеер (iOS / Android): матовый тёмный интерфейс, офлайн-режим, YouTube Music через пул зеркал Piped/Invidious, Spotify через Cloudflare Worker-прокси, синхронизированные тексты из LRCLIB.

## Возможности

- **Поиск и стриминг**: Piped + Invidious с авто-фолбэком (таймаут 3 с), свой инстанс в настройках, проксирование аудиопотока через Worker.
- **Spotify**: API через прокси (client id/secret опционально) либо парсинг публичных эмбедов без ключей.
- **Офлайн**: скачивание `.m4a`/`.opus`, обложки и `.lrc`; вкладка «Скачанные», менеджер кэша.
- **Свои треки**: импорт mp3/m4a/flac/wav/ogg/opus/aac, чтение ID3-тегов и обложек, правка тегов, поиск текста в LRCLIB, импорт `.lrc`/`.txt`, ручная вставка.
- **Плеер**: фон и экран блокировки (audio_service), очередь с перетаскиванием, shuffle/repeat, таймер сна, выбор битрейта, кроссфейд-настройка.
- **Караоке-текст** с автоскроллом по таймкодам.
- **Медиатека**: JSON-экспорт/импорт, импорт плейлистов Spotify по ссылке.

## Стек

Flutter 3.50 · just_audio · audio_service · audio_session · dio · hive_flutter · file_picker · permission_handler · path_provider · palette_generator · audio_metadata_reader · riverpod

## Структура

```
lib/
  app/           # шелл, провайдеры, навигация
  core/          # конфиг, тема, сеть (piped/spotify/lrclib/proxy), утилиты
  data/          # модели (Track, Playlist, Lyrics), репозитории
  services/      # аудиодвижок, скачивание, хранилище/импорт
  features/      # home, search, library, playlist, player, lyrics, create, settings
  shared/        # виджеты (коллаж, станции, трек-тайл, мини-плеер)
worker.js        # Cloudflare Worker reverse proxy
```

## Worker

Деплой `worker.js` в Cloudflare Workers. Переменные: `PIPED_ORIGIN`, `INVIDIOUS_ORIGIN`, `ALLOWED_HOSTS`, опционально `SPOTIFY_TOKEN`.

Маршруты: `/spotify/*`, `/accounts/*`, `/cdn/*`, `/embed/*`, `/piped/*`, `/invidious/*`, `/proxy?url=...`.

В приложении: Настройки → «Cloudflare Worker URL».

## Сборка

```bash
flutter pub get
flutter run
flutter build apk --release
```

## CI

Push в `main` → `YSPlayer-v<version>-android.apk` + `YSPlayer-v<version>-ios.ipa` (unsigned) → ветка `releases` и GitHub Release `v<version>`.

Версия: `1.0.<run_number - 1>+<run_number>` (первый прогон — `1.0.0+1`).
