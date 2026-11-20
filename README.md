# YSPlayer

Кроссплатформенный музыкальный плеер (iOS / Android): матовый тёмный UI, офлайн-режим, YouTube Music через пул зеркал Piped/Invidious, Spotify через Cloudflare Worker-прокси, тексты из LRCLIB.

## Стек

Flutter · just_audio · audio_service · dio · hive_flutter · file_picker · permission_handler · palette_generator · path_provider

## Структура

```
lib/
  app/          # MaterialApp, шелл, нижняя навигация
  core/theme/   # палитра и тема (Flat Dark, без blur)
  core/network/ # piped, spotify, lyrics
  data/         # модели, репозитории, источники
  features/     # home, search, library, playlist, player, settings, downloads, lyrics
  services/     # аудиодвижок, загрузки
  shared/       # общие виджеты
worker.js       # Cloudflare Worker reverse proxy (Spotify / Piped / Invidious / passthrough)
.github/workflows/build_release.yml
```

## Версионирование

`1.0.<run_number - 1>+<run_number>`; первый прогон CI — `1.0.0+1`.

## CI

Push в `main` → сборка `YSPlayer-v<version>-android.apk` и `YSPlayer-v<version>-ios.ipa` (unsigned) → ветка `releases` + GitHub Release `v<version>`.

## Worker

Деплой `worker.js` в Cloudflare Workers, переменные: `PIPED_ORIGIN`, `INVIDIOUS_ORIGIN`, `ALLOWED_HOSTS`, опционально `SPOTIFY_TOKEN`.

Маршруты: `/spotify/*`, `/cdn/*`, `/embed/*`, `/piped/*`, `/invidious/*`, `/proxy?url=...`.
