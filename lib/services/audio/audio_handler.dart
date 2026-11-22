import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/settings.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'audio_resolver_service.dart';

enum TrollRepeat { off, all, one }

class TrollAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  TrollAudioHandler({
    required LibraryRepository library,
    Settings? settings,
    this.resolver,
  })  : _library = library,
        _settings = settings;

  final LibraryRepository _library;
  final Settings? _settings;
  final AudioResolverService? resolver;

  final AudioPlayer _player = AudioPlayer();

  /// Прямые потоки идут через `LockCachingAudioSource`: повторное
  /// воспроизведение и перемотка без сети. HLS отдаётся нативному плееру,
  /// ещё не разрешённые треки очереди заменяются тишиной до подгрузки URL.
  IndexedAudioSource _source(Track track, MediaItem tag) {
    if (!_isResolved(track)) {
      return SilenceAudioSource(
        duration: track.duration > Duration.zero
            ? track.duration
            : const Duration(seconds: 3),
        tag: tag,
      );
    }
    final uri = _uriOf(track);
    final remote = uri.scheme == 'http' || uri.scheme == 'https';
    if (!remote) return AudioSource.uri(uri, tag: tag);

    final headers = _headersFor(uri.toString());
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      return AudioSource.uri(uri, tag: tag, headers: headers);
    }
    // ignore: experimental_member_use
    return LockCachingAudioSource(uri, headers: headers, tag: tag);
  }

  bool _isResolved(Track track) {
    final local = track.localPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) return true;
    final url = track.streamUrl;
    return url != null && url.isNotEmpty;
  }

  final _crossfade = ValueNotifier<Duration>(Duration.zero);
  final _shuffleEnabled = ValueNotifier<bool>(false);
  final _repeat = ValueNotifier<TrollRepeat>(TrollRepeat.off);
  final _sleepRemaining = ValueNotifier<Duration?>(null);
  final _errors = StreamController<String>.broadcast();

  final Map<String, Track> _tracks = {};
  final Map<String, List<String>> _candidates = {};
  List<Track> _playable = const [];

  Timer? _sleepTimer;
  Timer? _fadeTimer;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fading = false;
  bool _restoring = false;
  bool _recovering = false;
  bool _loading = false;
  bool _activating = false;
  final Set<String> _prefetching = {};

  Stream<String> get errors => _errors.stream;
  ValueNotifier<Duration> get crossfade => _crossfade;
  ValueNotifier<bool> get shuffleEnabled => _shuffleEnabled;
  ValueNotifier<TrollRepeat> get repeat => _repeat;
  ValueNotifier<Duration?> get sleepRemaining => _sleepRemaining;
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _restoreSettings();

    try {
      await _player.setAutomaticallyWaitsToMinimizeStalling(true);
    } catch (_) {
      // Не поддерживается платформой (Android).
    }

    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stack) => _handlePlaybackError(error),
    );
    _player.errorStream.listen(
      (_) => _handlePlaybackError('audio stream error'),
      onError: (Object error) => _handlePlaybackError(error),
    );
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.currentIndexStream.listen((index) {
      _prefetching.clear();
      _syncQueueIndex();
      _persistCurrentTrack();
      if (!_restoring) _fadeIn();
      unawaited(_activateIfUnresolved(index));
    });
    _player.positionStream.listen((position) {
      _maybeFadeOut(position);
      _maybePrefetch(position);
      _persistPosition(position);
    });
  }

  void _restoreSettings() {
    final settings = _settings;
    if (settings == null) return;
    _crossfade.value = Duration(seconds: settings.crossfadeSeconds);
    _shuffleEnabled.value = settings.shuffleEnabled;
    _repeat.value = TrollRepeat.values[settings.repeatIndex.clamp(0, 2)];
    _player.setLoopMode(_loopModeOf(_repeat.value));
    _player.setShuffleModeEnabled(_shuffleEnabled.value);
    _player.setSpeed(settings.playbackSpeed.clamp(0.5, 2.0));
  }

  Future<void> restoreLastPlayed() async {
    final settings = _settings;
    if (settings == null) return;
    final id = settings.lastTrackId;
    if (id == null || id.isEmpty) return;
    final track = _library.trackById(id);
    if (track == null) return;

    _restoring = true;
    try {
      await setLibraryQueue([track], autoPlay: false);
      final saved = Duration(milliseconds: settings.lastPositionMs);
      if (saved > Duration.zero) await _player.seek(saved);
    } catch (_) {
    } finally {
      _restoring = false;
    }
  }

  Future<void> setLibraryQueue(
    Iterable<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    final requested = tracks.toList();
    if (requested.isEmpty) return;

    final anchor = requested[initialIndex.clamp(0, requested.length - 1)];
    final playable = await _prepare(requested, eager: {anchor.id});
    if (!playable.any((t) => t.id == anchor.id)) {
      _errors.add('Не удалось получить аудиопоток. Проверьте подключение к интернету.');
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }

    var index = playable.indexWhere((t) => t.id == anchor.id);
    if (index < 0) index = 0;

    queue.add(playable.map(_toMediaItem).toList());
    await _load(playable, index, autoPlay: autoPlay);
  }

  Future<void> playTrack(Track track, {List<Track>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((t) => t.id == track.id);
      await setLibraryQueue(contextQueue, initialIndex: index < 0 ? 0 : index);
      return;
    }
    await setLibraryQueue([track]);
  }

  Future<bool> playNext(Track track) async {
    final prepared = await _prepare([track]);
    if (prepared.isEmpty) return false;
    final resolved = prepared.first;
    _remember(resolved);

    final items = [...queue.value];
    final current = _player.currentIndex;
    final insertAt = current == null ? items.length : (current + 1).clamp(0, items.length);
    items.insert(insertAt, _toMediaItem(resolved));
    queue.add(items);

    try {
      final source = _source(resolved, _toMediaItem(resolved));
      await _player.insertAudioSource(insertAt, source);
      _playable = [..._playable]..insert(insertAt.clamp(0, _playable.length), resolved);
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<bool> addToQueue(Track track) async {
    final prepared = await _prepare([track]);
    if (prepared.isEmpty) return false;
    final resolved = prepared.first;
    _remember(resolved);

    final items = [...queue.value, _toMediaItem(resolved)];
    queue.add(items);

    try {
      final source = _source(resolved, _toMediaItem(resolved));
      await _player.addAudioSource(source);
      _playable = [..._playable, resolved];
    } catch (_) {
      return false;
    }
    return true;
  }

  void _remember(Track track, {List<String>? urls}) {
    _tracks[track.id] = track;
    if (urls != null && urls.isNotEmpty) _candidates[track.id] = urls;
  }

  /// Разрешает URL только для треков из [eager] (`null` — для всех).
  /// Остальные остаются заглушками и подгружаются при переходе/предзагрузке.
  Future<List<Track>> _prepare(Iterable<Track> tracks, {Set<String>? eager}) async {
    final list = tracks.toList();
    final results = List<Track?>.filled(list.length, null);
    final pending = <int>[];

    for (var i = 0; i < list.length; i++) {
      final track = list[i];
      if (_isResolved(track) || (eager != null && !eager.contains(track.id))) {
        results[i] = track;
        continue;
      }
      pending.add(i);
    }

    if (resolver == null || pending.isEmpty) {
      return results.whereType<Track>().toList();
    }

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final index = pending[cursor++];
        final track = list[index];
        final urls = await _resolveSafe(track);
        if (urls.isNotEmpty) {
          final resolved = _withStreamUrl(track, urls.first);
          results[index] = resolved;
          _remember(resolved, urls: urls);
        }
      }
    }

    final workers = pending.length < 4 ? pending.length : 4;
    await Future.wait(List.generate(workers, (_) => worker()))
        .timeout(const Duration(seconds: 10), onTimeout: () => const []);

    return results.whereType<Track>().toList();
  }

  Uri _uriOf(Track track) {
    final local = track.localPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      return Uri.file(local);
    }
    return Uri.parse(track.streamUrl!);
  }

  Future<List<String>> _resolveSafe(Track track) async {
    final r = resolver;
    if (r == null) return const [];
    try {
      return await r.resolve(track).timeout(const Duration(seconds: 15));
    } catch (_) {
      return const [];
    }
  }

  /// `copyWith` не умеет перезаписывать уже заданный `streamUrl`, поэтому
  /// собираем трек заново при смене источника.
  Track _withStreamUrl(Track track, String? url) => Track(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        thumbnailUrl: track.thumbnailUrl,
        streamUrl: url,
        localPath: track.localPath,
        lyricsPath: track.lyricsPath,
        artworkPath: track.artworkPath,
        explicit: track.explicit,
        source: track.source,
        bitrate: track.bitrate,
        albumId: track.albumId,
      );

  Map<String, String> _headersFor(String url) => {
        ...?resolver?.streamHeaders(url),
        ...?_settings?.requestHeaders,
      };

  Future<void> _load(
    List<Track> tracks,
    int index, {
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    for (final track in tracks) {
      _remember(track);
    }
    final items = tracks
        .map((t) => _source(t, _toMediaItem(t)))
        .toList();
    final target = index.clamp(0, items.length - 1);
    _playable = tracks;
    mediaItem.add(items[target].tag as MediaItem);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    _loading = true;
    try {
      await _player.setAudioSources(
        items,
        initialIndex: target,
        initialPosition: Duration.zero,
      );
      await _player.setVolume(1);
      if (autoPlay) {
        unawaited(play());
      }
    } catch (_) {
      await _tryAlternatives(target);
    } finally {
      _loading = false;
    }
  }

  Future<void> playAt(int index) async {
    final sequence = _player.sequenceState.sequence;
    if (index < 0 || index >= sequence.length) return;
    await _player.setVolume(1);
    await _player.seek(Duration.zero, index: index);
    unawaited(play());
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final items = [...queue.value];
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), moved);
    queue.add(items);
    if (oldIndex < _playable.length) {
      final playable = [..._playable];
      final movedTrack = playable.removeAt(oldIndex);
      playable.insert(newIndex.clamp(0, playable.length), movedTrack);
      _playable = playable;
    }
    await _player.moveAudioSource(oldIndex, newIndex);
  }

  Future<void> removeFromQueue(int index) async {
    final items = [...queue.value];
    if (index < 0 || index >= items.length) return;

    final currentIndex = _player.currentIndex ?? 0;
    final wasPlaying = _player.playing;
    final anchorId =
        currentIndex >= 0 && currentIndex < items.length ? items[currentIndex].id : null;

    items.removeAt(index);
    if (items.isEmpty) {
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      _playable = const [];
      await _player.stop();
      return;
    }

    final tracks = items
        .map((item) => _tracks[item.id] ?? _library.trackById(item.id))
        .whereType<Track>()
        .toList();
    final fallbackId = items[index.clamp(0, items.length - 1)].id;
    final playable = await _prepare(
      tracks,
      eager: {if (anchorId != null) anchorId, fallbackId},
    );
    if (playable.isEmpty) {
      queue.add(items);
      return;
    }

    var target = playable.indexWhere((t) => t.id == anchorId);
    if (target < 0) target = index.clamp(0, playable.length - 1);

    queue.add(playable.map(_toMediaItem).toList());
    await _load(playable, target, autoPlay: wasPlaying);
  }

  Future<void> clearQueue() async {
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    _playable = const [];
    _candidates.clear();
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> play() async {
    if (_player.volume < 1) await _player.setVolume(1);
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _persistPosition(_player.position, force: true);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _persistPosition(_player.position, force: true);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (!_player.hasNext) {
      if (_repeat.value == TrollRepeat.all && _player.sequenceState.sequence.isNotEmpty) {
        await _player.seek(Duration.zero, index: 0);
        unawaited(play());
      }
      return;
    }
    await _player.seekToNext();
    unawaited(play());
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
      return;
    }
    await _player.seekToPrevious();
    unawaited(play());
  }

  Future<void> setShuffle(bool enabled) async {
    _shuffleEnabled.value = enabled;
    await _player.setShuffleModeEnabled(enabled);
    if (enabled) await _player.shuffle();
    _settings?.shuffleEnabled = enabled;
  }

  Future<void> cycleRepeat() async {
    final next = switch (_repeat.value) {
      TrollRepeat.off => TrollRepeat.all,
      TrollRepeat.all => TrollRepeat.one,
      TrollRepeat.one => TrollRepeat.off,
    };
    _repeat.value = next;
    await _player.setLoopMode(_loopModeOf(next));
    _settings?.repeatIndex = TrollRepeat.values.indexOf(next);
  }

  Future<void> setCrossfade(Duration value) async {
    _crossfade.value = value;
    _settings?.crossfadeSeconds = value.inSeconds;
    if (value == Duration.zero) {
      _fadeTimer?.cancel();
      _fading = false;
      await _player.setVolume(1);
    }
  }

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepRemaining.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining =
          (_sleepRemaining.value ?? Duration.zero) - const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        timer.cancel();
        _sleepRemaining.value = null;
        pause();
      } else {
        _sleepRemaining.value = remaining;
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepRemaining.value = null;
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _settings?.playbackSpeed = speed;
  }

  Lyrics? lyricsForCurrent() {
    final item = mediaItem.value;
    if (item == null) return null;
    final raw = _library.lyricsFor(item.id);
    return raw == null ? null : LrcParser.parse(raw);
  }

  void _handlePlaybackError(Object error) {
    debugPrint('$error');
    if (_loading || _recovering) return;
    unawaited(_recoverFromError());
  }

  Future<void> _recoverFromError() async {
    if (_recovering) return;
    _recovering = true;
    try {
      final index = _player.currentIndex;
      final track = _currentTrack(index);
      if (track == null) {
        _emitError('Не удалось воспроизвести трек');
        return;
      }

      if (index != null) {
        final recovered = await _tryAlternatives(index);
        if (recovered) return;
      }

      if (_player.hasNext) {
        _errors.add('Трек недоступен, включаю следующий');
        try {
          await _player.seekToNext();
          await play();
          return;
        } catch (_) {}
      }

      _emitError('Не удалось воспроизвести трек');
    } finally {
      _recovering = false;
    }
  }

  Track? _currentTrack(int? index) {
    if (index != null && index >= 0 && index < _playable.length) {
      return _playable[index];
    }
    final item = mediaItem.value;
    if (item == null) return null;
    return _tracks[item.id] ?? _library.trackById(item.id);
  }

  /// Пробует следующие URL-кандидаты для трека по индексу.
  Future<bool> _tryAlternatives(int index) async {
    if (index < 0 || index >= _playable.length) return false;
    var track = _playable[index];
    var urls = _candidates[track.id] ?? const <String>[];
    final current = track.streamUrl;
    final usable = urls.where((u) => u != current).toList();

    if (usable.isEmpty && resolver != null && track.source != TrackSource.local) {
      resolver!.forget(track.id);
      final fresh = await _resolveSafe(_withStreamUrl(track, null));
      if (fresh.isNotEmpty) {
        _candidates[track.id] = fresh;
        urls = fresh;
        for (final url in fresh) {
          if (url != current && !usable.contains(url)) usable.add(url);
        }
      }
    }

    for (final url in usable) {
      if (url.isEmpty) continue;
      try {
        final updated = _withStreamUrl(track, url);
        _playable = [..._playable];
        _playable[index] = updated;
        _remember(updated, urls: urls);
        await _player.setAudioSources(
          [for (final t in _playable) _source(t, _toMediaItem(t))],
          initialIndex: index,
          initialPosition: Duration.zero,
        );
        await _player.setVolume(1);
        await play();
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Подгружает URL для трека-заглушки, на который перешёл плеер.
  Future<void> _activateIfUnresolved(int? index) async {
    if (index == null || index < 0 || index >= _playable.length) return;
    if (_isResolved(_playable[index]) || _loading || _recovering || _activating) return;

    _activating = true;
    try {
      final track = _playable[index];
      final urls = await _resolveSafe(track);
      final at = _playable.indexWhere((t) => t.id == track.id);
      if (at < 0) return;

      if (urls.isEmpty) {
        if (_player.currentIndex != at) return;
        if (_player.hasNext) {
          _errors.add('Трек недоступен, включаю следующий');
          await _player.seekToNext();
          unawaited(play());
        } else {
          _emitError('Не удалось воспроизвести трек');
        }
        return;
      }

      _applyResolved(at, urls);
      if (_player.currentIndex == at) {
        final wasPlaying = _player.playing;
        await _player.setAudioSources(
          [for (final t in _playable) _source(t, _toMediaItem(t))],
          initialIndex: at,
          initialPosition: Duration.zero,
        );
        await _player.setVolume(1);
        if (wasPlaying) unawaited(play());
      } else {
        await _swapSource(at);
      }
    } catch (error) {
      debugPrint('activate: $error');
    } finally {
      _activating = false;
      final current = _player.currentIndex;
      if (current != null && current != index) {
        unawaited(_activateIfUnresolved(current));
      }
    }
  }

  void _maybePrefetch(Duration position) {
    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    if (duration - position > AppConfig.prefetchBefore) return;
    if (_repeat.value == TrollRepeat.one) return;
    final next = _player.nextIndex;
    if (next == null || next < 0 || next >= _playable.length) return;
    final track = _playable[next];
    if (_isResolved(track) || !_prefetching.add(track.id)) return;
    unawaited(_prefetch(track));
  }

  Future<void> _prefetch(Track track) async {
    try {
      final urls = await _resolveSafe(track);
      if (urls.isEmpty) return;
      final at = _playable.indexWhere((t) => t.id == track.id);
      if (at < 0 || _isResolved(_playable[at]) || at == _player.currentIndex) return;
      _applyResolved(at, urls);
      await _swapSource(at);
    } catch (error) {
      debugPrint('prefetch: $error');
    }
  }

  void _applyResolved(int index, List<String> urls) {
    final updated = _withStreamUrl(_playable[index], urls.first);
    _playable = [..._playable]..[index] = updated;
    _remember(updated, urls: urls);
  }

  Future<void> _swapSource(int index) async {
    final track = _playable[index];
    final source = _source(track, _toMediaItem(track));
    await _player.removeAudioSourceAt(index);
    await _player.insertAudioSource(index, source);
  }

  void _emitError(String message) {
    _errors.add(message);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.error,
      playing: false,
    ));
  }

  void _maybeFadeOut(Duration position) {
    final fade = _crossfade.value;
    if (fade == Duration.zero || _fading) return;
    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    if (_repeat.value == TrollRepeat.one) return;
    final remaining = duration - position;
    if (remaining <= fade && remaining > const Duration(milliseconds: 120)) {
      _fadeTo(0, remaining);
    }
  }

  void _fadeIn() {
    if (_crossfade.value == Duration.zero) {
      unawaited(_player.setVolume(1));
      return;
    }
    _fadeTo(1, const Duration(milliseconds: 700));
  }

  void _fadeTo(double target, Duration over) {
    _fadeTimer?.cancel();
    _fading = true;
    final steps = (over.inMilliseconds / 80).ceil().clamp(1, 120);
    final start = _player.volume;
    var step = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      step++;
      final value = start + (target - start) * (step / steps);
      unawaited(_player.setVolume(value.clamp(0.0, 1.0)));
      if (step >= steps || (timer.tick * 80) >= over.inMilliseconds) {
        timer.cancel();
        _fading = false;
      }
    });
  }

  void _persistPosition(Duration position, {bool force = false}) {
    final settings = _settings;
    if (settings == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPositionSave) < const Duration(seconds: 5)) {
      return;
    }
    _lastPositionSave = now;
    settings.lastPositionMs = position.inMilliseconds;
  }

  void _persistCurrentTrack() {
    final settings = _settings;
    if (settings == null) return;
    final item = mediaItem.value;
    if (item == null) return;
    settings.lastTrackId = item.id;
    settings.lastPositionMs = 0;
    if (!_restoring) settings.recordPlay(item.id);
  }

  void _onCompleted() {
    if (_repeat.value == TrollRepeat.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.completed),
    );
  }

  void _syncQueueIndex() {
    final index = _player.currentIndex;
    final items = queue.value;
    if (index == null || index < 0 || index >= items.length) return;
    mediaItem.add(items[index]);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        repeatMode: switch (_repeat.value) {
          TrollRepeat.off => AudioServiceRepeatMode.none,
          TrollRepeat.all => AudioServiceRepeatMode.all,
          TrollRepeat.one => AudioServiceRepeatMode.one,
        },
        shuffleMode: _shuffleEnabled.value
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  LoopMode _loopModeOf(TrollRepeat mode) => switch (mode) {
        TrollRepeat.off => LoopMode.off,
        TrollRepeat.all => LoopMode.all,
        TrollRepeat.one => LoopMode.one,
      };

  MediaItem _toMediaItem(Track track) => MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        artUri: _artUri(track),
        extras: {'source': track.source.name},
      );

  Uri? _artUri(Track track) {
    if (track.artworkPath != null && track.artworkPath!.isNotEmpty) {
      return Uri.file(track.artworkPath!);
    }
    if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty) {
      return Uri.parse(track.thumbnailUrl!);
    }
    return null;
  }
}
