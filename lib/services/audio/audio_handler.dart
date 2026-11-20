import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/storage/settings.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

enum YsRepeat { off, all, one }

class YsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  YsAudioHandler({
    required LibraryRepository library,
    Settings? settings,
    this.resolveStream,
  })  : _library = library,
        _settings = settings;

  final LibraryRepository _library;
  final Settings? _settings;
  final Future<String?> Function(String videoId)? resolveStream;

  final AudioPlayer _player = AudioPlayer();

  /// Сетевые потоки — через локальный кэширующий прокси just_audio: повтор без
  /// сети и обход блокировок через HTTP-прокси приложения (нативный плеер его не видит).
  IndexedAudioSource _source(String location, MediaItem tag) {
    final uri = Uri.parse(location);
    final remote = uri.scheme == 'http' || uri.scheme == 'https';
    final s = _settings;
    if (remote && s != null && (s.audioCache || s.httpProxy.isNotEmpty)) {
      return LockCachingAudioSource(uri, tag: tag);
    }
    return AudioSource.uri(uri, tag: tag);
  }

  final _crossfade = ValueNotifier<Duration>(Duration.zero);
  final _shuffleEnabled = ValueNotifier<bool>(false);
  final _repeat = ValueNotifier<YsRepeat>(YsRepeat.off);
  final _sleepRemaining = ValueNotifier<Duration?>(null);
  final _errors = StreamController<String>.broadcast();

  Timer? _sleepTimer;
  Timer? _fadeTimer;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fading = false;
  bool _restoring = false;

  Stream<String> get errors => _errors.stream;
  ValueNotifier<Duration> get crossfade => _crossfade;
  ValueNotifier<bool> get shuffleEnabled => _shuffleEnabled;
  ValueNotifier<YsRepeat> get repeat => _repeat;
  ValueNotifier<Duration?> get sleepRemaining => _sleepRemaining;
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _restoreSettings();

    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stack) => _handlePlaybackError(error),
    );
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.currentIndexStream.listen((_) {
      _syncQueueIndex();
      _persistCurrentTrack();
      if (!_restoring) _fadeIn();
    });
    _player.positionStream.listen((position) {
      _maybeFadeOut(position);
      _persistPosition(position);
    });
  }

  void _restoreSettings() {
    final settings = _settings;
    if (settings == null) return;
    _crossfade.value = Duration(seconds: settings.crossfadeSeconds);
    _shuffleEnabled.value = settings.shuffleEnabled;
    _repeat.value = YsRepeat.values[settings.repeatIndex.clamp(0, 2)];
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
    final playable = await _prepare(requested, anchorId: anchor.id);
    if (playable.isEmpty) {
      _errors.add('Не удалось получить аудиопоток. Проверьте зеркала в настройках.');
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

    final items = [...queue.value];
    final current = _player.currentIndex;
    final insertAt = current == null ? items.length : (current + 1).clamp(0, items.length);
    items.insert(insertAt, _toMediaItem(resolved));
    queue.add(items);

    try {
      final source = _source(
        resolved.localPath ?? resolved.streamUrl!,
        _toMediaItem(resolved),
      );
      await _player.insertAudioSource(insertAt, source);
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<bool> addToQueue(Track track) async {
    final prepared = await _prepare([track]);
    if (prepared.isEmpty) return false;
    final resolved = prepared.first;

    final items = [...queue.value, _toMediaItem(resolved)];
    queue.add(items);

    try {
      final source = _source(
        resolved.localPath ?? resolved.streamUrl!,
        _toMediaItem(resolved),
      );
      await _player.addAudioSource(source);
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<List<Track>> _prepare(Iterable<Track> tracks, {String? anchorId}) async {
    final list = tracks.toList();
    final results = List<Track?>.filled(list.length, null);
    final pending = <int>[];

    for (var i = 0; i < list.length; i++) {
      final track = list[i];
      final local = track.localPath;
      if (local != null && local.isNotEmpty && File(local).existsSync()) {
        results[i] = track;
        continue;
      }
      final known = track.streamUrl;
      if (known != null && known.isNotEmpty) {
        results[i] = track;
        continue;
      }
      pending.add(i);
    }

    final resolve = resolveStream;
    if (resolve == null || pending.isEmpty) {
      return results.whereType<Track>().toList();
    }

    if (anchorId != null) {
      final anchorIndex = pending.indexWhere((i) => list[i].id == anchorId);
      if (anchorIndex > 0) {
        final anchor = pending.removeAt(anchorIndex);
        pending.insert(0, anchor);
      }
    }

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final index = pending[cursor++];
        final track = list[index];
        String? url;
        try {
          url = await resolve(track.id);
        } catch (_) {
          url = null;
        }
        if (url != null && url.isNotEmpty) {
          results[index] = track.copyWith(streamUrl: url);
        }
      }
    }

    final workers = pending.length < 4 ? pending.length : 4;
    await Future.wait(List.generate(workers, (_) => worker()))
        .timeout(const Duration(seconds: 8), onTimeout: () => const []);

    return results.whereType<Track>().toList();
  }

  Future<void> _load(
    List<Track> tracks,
    int index, {
    bool autoPlay = true,
  }) async {
    final items = tracks
        .map((t) => _source(t.localPath ?? t.streamUrl!, _toMediaItem(t)))
        .toList();
    final target = index.clamp(0, items.length - 1);
    mediaItem.add(items[target].tag as MediaItem);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    await _player.setAudioSources(
      items,
      initialIndex: target,
      initialPosition: Duration.zero,
    );
    await _player.setVolume(1);
    if (autoPlay) {
      unawaited(play());
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
      await _player.stop();
      return;
    }

    final tracks =
        items.map((item) => _library.trackById(item.id)).whereType<Track>().toList();
    final playable = await _prepare(tracks);
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
      if (_repeat.value == YsRepeat.all && _player.sequenceState.sequence.isNotEmpty) {
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
      YsRepeat.off => YsRepeat.all,
      YsRepeat.all => YsRepeat.one,
      YsRepeat.one => YsRepeat.off,
    };
    _repeat.value = next;
    await _player.setLoopMode(_loopModeOf(next));
    _settings?.repeatIndex = YsRepeat.values.indexOf(next);
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
    unawaited(_recoverFromError());
  }

  Future<void> _recoverFromError() async {
    final index = _player.currentIndex;
    final items = queue.value;
    if (index == null || index < 0 || index >= items.length) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
      ));
      return;
    }

    final item = items[index];
    final track = _library.trackById(item.id);
    final resolve = resolveStream;
    final needsFresh = track != null &&
        (track.localPath == null || track.localPath!.isEmpty) &&
        resolve != null;

    if (needsFresh) {
      String? url;
      try {
        url = await resolve(track.id);
      } catch (_) {
        url = null;
      }
      if (url != null && url.isNotEmpty) {
        try {
          await _player.setAudioSource(
            _source(url, item),
            initialIndex: index,
          );
          await _player.setVolume(1);
          await play();
          return;
        } catch (_) {}
      }
    }

    if (_player.hasNext) {
      _errors.add('Трек недоступен, включаю следующий');
      try {
        await _player.seekToNext();
        await play();
        return;
      } catch (_) {}
    }

    _errors.add('Не удалось воспроизвести трек');
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
    if (_repeat.value == YsRepeat.one) return;
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
    if (_repeat.value == YsRepeat.one) {
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
          YsRepeat.off => AudioServiceRepeatMode.none,
          YsRepeat.all => AudioServiceRepeatMode.all,
          YsRepeat.one => AudioServiceRepeatMode.one,
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

  LoopMode _loopModeOf(YsRepeat mode) => switch (mode) {
        YsRepeat.off => LoopMode.off,
        YsRepeat.all => LoopMode.all,
        YsRepeat.one => LoopMode.one,
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
