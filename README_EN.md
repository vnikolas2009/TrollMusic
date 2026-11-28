# TrollMusic

A local music player for iOS and Android built with Flutter. Your library comes from your own files: no accounts, tokens, subscriptions or backend. Its highlight is a lyrics screen with synced, word-by-word highlighting (enhanced LRC).

Russian version: [README.md](README.md). Project structure: [ARCHITECTURE.md](ARCHITECTURE.md).

## Features

### Library
- Import files (MP3, M4A, FLAC, WAV, OGG, Opus, AAC, WMA, ALAC, AIFF) and scan folders, either incremental (changed files only) or full.
- Tags, artwork and embedded lyrics are read from the files. Without tags, artist and title come from the file name ("Artist - Title.mp3").
- Tabs: all tracks, playlists, artists, albums, favorites. Sorting (recent, title, artist, album, duration, most played) and an "only without lyrics" filter.
- Search by title, artist, album and by a line of the lyrics.
- Playlists: create, add tracks, reorder, rename. Track menu: play next, add to queue, favorite, tags and artwork, delete.
- An "only without artwork" filter and adding artwork one by one (for each track you can pick a file, skip it or stop).
- Confirmation before deleting a track, playlist, lyrics or imported font, and before clearing the queue or history.
- Library backup to JSON.
- Search for tracks on the web: Import tab → built-in browser. When audio starts playing on a page, or a direct link to an audio file is opened, the app offers to download it to your library. Streams without a direct file (YouTube, Spotify, etc.) cannot be downloaded.

### Player
- Queue with reordering, repeat, 0.5–2× speed, crossfade, skip silence (Android), sleep timer by minutes or "until the end of the track".
- Shuffle: the "shuffle" buttons support **smart** ordering: recently played tracks move toward the end, rarely played ones tend to come first, and tracks by the same artist avoid playing back to back where possible (can be turned off in settings).
- Session restore: after a restart the queue, current track and position in it come back. The position is saved on pause, on track change and when the app goes to the background. Files that are no longer available are skipped.
- The sleep timer smoothly lowers the volume over the last 45 seconds (20 seconds in "until the end of the track" mode) and then pauses.
- Listening statistics (Settings): top tracks and artists for the week, the month or the whole log (last 3000 plays), plus an estimate of listening time. The log has been kept since the update to version 2.0.
- Swipe the cover or the mini player to change tracks, tap the time to show the remaining time, and see the current lyric line under the cover.
- A broken file is skipped and the queue keeps playing. Media notification and lock-screen controls.

### Lyrics
Lyrics are picked up in several ways:
1. A `.lrc` / `.elrc` / `.txt` file next to the audio, or selected together with it.
2. Batch import: files are matched to tracks by audio file name, title, "Artist - Title" and the `[ti:]` / `[ar:]` tags.
3. File tags (ID3/Vorbis).
4. Online: LRCLIB, Kugou (word timing), QQ Music, Lyrics.ovh. The best candidate is chosen by title, artist and duration; enhanced LRC wins over LRC, which wins over plain text. Lyrics with masked words lose to uncensored ones, and a version whose duration differs a lot is shown without timestamps.
5. Manually: paste text or load a file.

On the lyrics screen: word-by-word highlighting, three styles (Spotify-like, minimal, classic), text size, per-track sync offset, tap a line to seek, long-press to loop a line, and a custom PNG/JPG/WebP/GIF background under a dim or gradient overlay. All of these live in the "Аа" sheet in the screen header.

**Practice mode.** A switch in the "Аа" sheet hides some words in lines that have not been sung yet; sung lines are revealed so you can check yourself. It works for lyrics with timestamps and is not kept between launches. Lyric lines appear in a wave when the screen opens.

**Translation.** The translate button in the header shows a translation of the chosen language (12 languages) under each line. The original, including timestamps and enhanced LRC word timing, is never modified: the translation is stored separately and aligned to lines. Finished translations are cached on the device, so no network is needed again; the cache is refreshed if the lyrics change. Translation uses a free, unofficial Google Translate endpoint without a key, so it may change or become unavailable.

### Appearance
- Themes (dark, light, system, AMOLED), accent color, gradient background.
- Custom fonts (TTF/OTF) plus built-in Inter and Manrope, four weight levels and interface text size.
- Bottom bar: reorder the tabs by dragging and hide the ones you do not need (Settings cannot be hidden, at least two tabs stay visible).
- Screen transitions: the new screen slides in with a fade, the previous one recedes.
- Animations: a "like" heart with particles, a pulsing ring around the play button, and a cover that shrinks on pause (disabled by the "minimal" mode and the system setting).
- Animation modes (smooth, fast, calm, minimal), effects level, cover shape.

### Home
A banner linking to the TrollCerts channel, "continue", daily pick, recently added, recently played, most played, a "without lyrics" card and a list of playlists.

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Release builds (Android APK, iOS IPA) are started manually via the `.github/workflows/build_release.yml` workflow.

The network is used only for online lyrics search and translation, the built-in browser and the channel link; everything else works offline.
