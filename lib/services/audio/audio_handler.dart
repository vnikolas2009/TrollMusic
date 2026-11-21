import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/http_client.dart';
import '../../core/network/youtube/stream_candidate.dart';
import '../../core/storage/settings.dart';
import '../../core/utils/audio_pick.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'resolved_stream_source.dart';

enum TrollRepeat { off, all, one }

typedef TrollStreamResolver = StreamResolver;

class TrollAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  TrollAudioHandler({
    required LibraryRepository library,
    Settings? settings,
    this.resolveStreams,
  })  : _library = library,
        _settings = settings,
        _dio = createDio(
          settings: settings,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 30),
        );

  final LibraryRepository _library;
  final Settings? _settings;
  final TrollStreamResolver? resolveStreams;
  final Dio _dio;

  /// Буферизация: на Android — 30–90 с вперёд, старт после 1,5 с данных;
  /// на iOS — AVPlayer сам ждёт, чтобы не заикаться.
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 30),
        maxBufferDuration: Duration(seconds: 90),
        bufferForPlaybackDuration: Duration(milliseconds: 1500),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 4),
        prioritizeTimeOverSizeThresholds: true,
      ),
      darwinLoadControl: DarwinLoadControl(
        automaticallyWaitsToMinimizeStalling: true,
        preferredForwardBufferDuration: Duration(seconds: 30),
      ),
    ),
  );

  bool _hasFile(Track track) {
    final local = track.localPath;
    return local != null && local.isNotEmpty && File(local).existsSync();
  }

  /// Скачанные и локальные файлы играют напрямую; всё остальное — потоком,
  /// ссылка на который разрешается лениво (см. [ResolvedStreamSource]).
  IndexedAudioSource _source(Track track, MediaItem tag) {
    if (_hasFile(track)) {
      return AudioSource.uri(Uri.file(track.localPath!), tag: tag);
    }
    final resolver = resolveStreams;
    if (resolver == null) {
      throw StateError('Нет резолвера потоков для ${track.id}');
    }
    final fresh = _freshIds.remove(track.id);
    return ResolvedStreamSource(
      track: track,
      resolve: resolver,
      dio: _dio,
      fresh: fresh,
      tag: tag,
      onResolved: _onResolved,
    );
  }

  void _onResolved(Track track, StreamCandidate candidate) {
    _loudness[track.id] = candidate.loudnessDb;
    final current = mediaItem.value;
    if (current != null && current.id == track.id) _applyNormalization();
  }

  /// Громкость треков, выданная YouTube (для выравнивания).
  final Map<String, double?> _loudness = {};
  final Set<String> _freshIds = {};
  final Set<String> _retried = {};
  double _gain = 1.0;
  double _fadeLevel = 1.0;

  void _applyNormalization() {
    final enabled = _settings?.normalizeVolume ?? false;
    final item = mediaItem.value;
    final db = item == null ? null : _loudness[item.id];
    _gain = enabled ? loudnessGain(db) : 1.0;
    unawaited(_player.setVolume((_fadeLevel * _gain).clamp(0.0, 1.0)));
  }

  Future<void> _setLevel(double level) {
    _fadeLevel = level.clamp(0.0, 1.0);
    return _player.setVolume((_fadeLevel * _gain).clamp(0.0, 1.0));
  }

  /// Для переключателя «Нормализация громкости» в настройках.
  void refreshNormalization() => _applyNormalization();

  final _crossfade = ValueNotifier<Duration>(Duration.zero);
  final _shuffleEnabled = ValueNotifier<bool>(false);
  final _repeat = ValueNotifier<TrollRepeat>(TrollRepeat.off);
  final _sleepRemaining = ValueNotifier<Duration?>(null);
  final _errors = StreamController<String>.broadcast();

  final Map<String, Track> _tracks = {};
  List<Track> _playable = const [];

  Timer? _sleepTimer;
  Timer? _fadeTimer;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fading = false;
  bool _restoring = false;
  bool _recovering = false;
  bool _loading = false;

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
    _player.currentIndexStream.listen((_) {
      _syncQueueIndex();
      _persistCurrentTrack();
      _applyNormalization();
      _warmNext();
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
    final playable = await _prepare(requested);
    if (playable.isEmpty) {
      _errors.add('Нет треков, которые можно воспроизвести');
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

  void _remember(Track track) {
    _tracks[track.id] = track;
  }

  /// Ссылки на потоки больше не разрешаются заранее (они протухают), поэтому
  /// здесь остаётся только отбор треков, которые вообще можно играть:
  /// сетевые — всегда, локальные — только если файл на месте.
  Future<List<Track>> _prepare(Iterable<Track> tracks) async {
    return [
      for (final track in tracks)
        if (track.source != TrackSource.local || _hasFile(track)) track,
    ];
  }

  /// Заранее разрешает ссылку на следующий трек (гладкий переход).
  void _warmNext() {
    if (!(_settings?.gaplessEnabled ?? true)) return;
    final resolver = resolveStreams;
    final next = _player.nextIndex;
    if (resolver == null || next == null) return;
    if (next < 0 || next >= _playable.length) return;
    final track = _playable[next];
    if (_hasFile(track)) return;
    unawaited(resolver(track).then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> _load(
    List<Track> tracks,
    int index, {
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    _retried.clear();
    for (final track in tracks) {
      _remember(track);
    }
    final target = index.clamp(0, tracks.length - 1);
    _playable = tracks;
    mediaItem.add(_toMediaItem(tracks[target]));
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    _loading = true;
    try {
      final items = [for (final t in tracks) _source(t, _toMediaItem(t))];
      final loading = _player.setAudioSources(
        items,
        initialIndex: target,
        initialPosition: Duration.zero,
      );
      // Воспроизведение стартует сразу, как только поток будет готов:
      // пользователь видит «играет», а не зависшую кнопку.
      if (autoPlay) unawaited(play());
      await loading.timeout(const Duration(seconds: 30));
      _applyNormalization();
    } catch (error) {
      debugPrint('load failed: $error');
      _loading = false;
      await _recoverFromError(atIndex: target);
    } finally {
      _loading = false;
    }
  }

  Future<void> playAt(int index) async {
    final sequence = _player.sequenceState.sequence;
    if (index < 0 || index >= sequence.length) return;
    await _setLevel(1);
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
    _playable = const [];
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> play() async {
    if (_fadeLevel < 1) await _setLevel(1);
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
      await _setLevel(1);
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

  Future<void> _recoverFromError({int? atIndex}) async {
    if (_recovering) return;
    _recovering = true;
    try {
      final index = atIndex ?? _player.currentIndex;
      final track = _currentTrack(index);
      if (track == null) {
        _emitError('Не удалось воспроизвести трек');
        return;
      }

      // Одна повторная попытка со свежими ссылками от всех источников.
      if (index != null && await _retryWithFreshLinks(index, track)) return;

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

  /// Пересобирает очередь, чтобы трек по [index] запросил свежие ссылки
  /// (кэш пропускается, опрашиваются все источники). Не более раза на трек.
  Future<bool> _retryWithFreshLinks(int index, Track track) async {
    if (index < 0 || index >= _playable.length) return false;
    if (track.source == TrackSource.local || _hasFile(track)) return false;
    if (resolveStreams == null || !_retried.add(track.id)) return false;

    try {
      _freshIds.add(track.id);
      final position = _player.position;
      await _player
          .setAudioSources(
            [for (final t in _playable) _source(t, _toMediaItem(t))],
            initialIndex: index,
            initialPosition: position,
          )
          .timeout(const Duration(seconds: 30));
      await _setLevel(1);
      unawaited(play());
      return true;
    } catch (error) {
      debugPrint('retry failed: $error');
      return false;
    }
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
      unawaited(_setLevel(1));
      return;
    }
    _fadeTo(1, const Duration(milliseconds: 700));
  }

  void _fadeTo(double target, Duration over) {
    _fadeTimer?.cancel();
    _fading = true;
    final steps = (over.inMilliseconds / 80).ceil().clamp(1, 120);
    final start = _fadeLevel;
    var step = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      step++;
      final value = start + (target - start) * (step / steps);
      unawaited(_setLevel(value));
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
