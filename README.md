# TrollMusic

Кроссплатформенный музыкальный плеер (iOS / Android) на Flutter: тёмный минималистичный интерфейс, офлайн-загрузки, синхронизированные тексты песен (LRCLIB). Работает в РФ без VPN и без платных сервисов.

## Как это работает

- **Метаданные Spotify** (плейлист, альбом, трек: название, исполнитель, длительность, обложка) отдаёт собственный бесплатный бэкенд на Vercel (`/api`). Аудио через него не проходит.
- **Аудио** приложение получает напрямую с CDN: сначала SoundCloud (MP3/HLS), при неудаче YouTube через InnerTube (`ANDROID_VR`/`IOS`).
- **DNS** для запросов приложения идёт через DNS-over-HTTPS (8.8.8.8 / 9.9.9.9), поэтому подмена DNS у провайдера не мешает.
- **Следующий трек** резолвится заранее, за 15 секунд до конца текущего.

## Возможности

### Каталог и поиск
- Поиск по SoundCloud, YouTube, Яндекс Музыке, Audius и (с личным токеном) VK Музыке, история запросов, поиск по медиатеке.
- Переключатель источника на главной и в поиске: Spotify, YouTube Music, Яндекс Музыка, VK Музыка, Audius.
- **Audius** играет напрямую без ключей. **Яндекс Музыка**: поиск и чарт без токена, прямой звук с личным OAuth-токеном (Настройки → Источники музыки), иначе подбор на SoundCloud/YouTube. **VK Музыка** работает только с личным токеном, и VK может закрыть доступ к методам музыки для конкретного токена.
- Импорт плейлистов и альбомов Spotify по ссылке без ключей и OAuth. Spotify-треки воспроизводятся через подбор совпадения на SoundCloud/YouTube.

### Плеер
- Ползунок таймкода (`shared/widgets/scrubber.dart`): seek один раз при отпускании, подсказка времени, буфер, ±10 секунд, пружинные анимации.

### Анимации (DesignBookmark Motion)
- Пружины перенесены с теми же значениями жёсткости и демпфирования, что в `tokens.css` (`core/motion/spring.dart`, `SpringTokens`); при «Убрать анимацию» в системе пружины становятся критически демпфированными (без перелёта).
- **Read along** (`shared/widgets/read_along_text.dart`): на экране текста песни за читаемым словом активной строки едет растягивающаяся пилюля.
- **Toggle switch** (`shared/widgets/spring_switch.dart`) и **Rubber dock** (`shared/widgets/rubber_dock.dart`): переключатели в Настройках — Toggle switch; нижняя навигация — Rubber dock (тап по вкладке или перетаскивание «пилюли» вбок).
- **Настройки** — отдельная (пятая) вкладка дока. Мини-плеер стоит над доком на всех вкладках, как только запущен трек.

### Оформление
- Новая иконка приложения (`tool/gen_icon.py` пересоздаёт её для Android и iOS), надпись TrollMusic с мерцающим акцентным градиентом (`brand_wordmark.dart`), медленно плывущее свечение за экранами (`aurora_background.dart`; отключается при «Убрать анимацию»).

### Главная
- Станции по артистам, миксы, «Подборка дня», недавно слушанное, тренды при пустой медиатеке.

### Плеер
- Фон и экран блокировки, очередь, shuffle/repeat, кроссфейд, таймер сна, скорость.
- Кэширование аудио на диск при прослушивании (`LockCachingAudioSource`).

### Тексты
- Анимированный фон из цвета обложки, активная строка заливается по времени, тап по строке перематывает.
- Сдвиг синхронизации, поиск в LRCLIB, импорт `.lrc`/`.txt`.

### Офлайн и библиотека
- Загрузки с прогрессом и отменой, локальные файлы с тегами, плейлисты, JSON-экспорт и импорт.

## Деплой бэкенда (Vercel, бесплатно)

```bash
npm i -g vercel
vercel --prod
```

Переменные окружения не нужны. Эндпоинты:

| Маршрут | Ответ |
|---|---|
| `GET /api/spotify/token` | `{accessToken, expiresAt}`: анонимный токен веб-плеера (кэш в памяти инстанса) |
| `GET /api/spotify/import?url=<ссылка>` | `{type, id, title, cover, tracks:[{id,title,artist,durationMs,cover}]}` для playlist/album/track |

Укажите полученный домен одним из способов:

- в настройках приложения, поле адреса API;
- при сборке: `--dart-define=TROLL_API_BASE=https://your-app.vercel.app`;
- в `AppConfig.defaultApiBase`.

## Стек

Flutter · just_audio · audio_service · audio_session · dio · hive_flutter · file_picker · permission_handler · path_provider · palette_generator · audio_metadata_reader · riverpod. Бэкенд: Vercel Serverless Functions (TypeScript).

## Структура

```
api/             # Vercel: /api/spotify/token, /api/spotify/import
lib/
  app/           # оболочка, провайдеры, сетевые зависимости
  core/          # конфиг, тема, сеть (DoH, SoundCloud, InnerTube, Spotify, Яндекс, VK, Audius, LRCLIB), хранилище
  data/          # модели (Track, Playlist, Lyrics), репозитории
  services/      # аудио (резолвер, обработчик), скачивание, импорт/хранилище
  features/      # home, search, library, playlist, artist, player, lyrics, create, settings
  shared/        # общие виджеты
vercel.json
```

Подробнее: [ARCHITECTURE.md](ARCHITECTURE.md).

## Сборка

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## CI

Push в `main` собирает `TrollMusic-v<version>-android.apk` и `TrollMusic-v<version>-ios.ipa` (unsigned), публикует их в ветку `releases` и GitHub Release `v<version>`. Версия: `1.0.<run_number - 1>+<run_number>`.
