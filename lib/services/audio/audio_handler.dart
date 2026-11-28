import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/storage/settings.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/loop_range.dart';
import '../../core/utils/play_counter.dart';
import '../../core/utils/session.dart';
import '../../core/utils/sleep_fade.dart';
import '../../core/utils/smart_shuffle.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

enum TrollRepeat { off, all, one }

/// Воспроизведение локальных файлов: очередь, повтор, перемешивание, скорость,
/// плавный переход, таймер сна, восстановление последнего трека.
class TrollAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  TrollAudioHandler({
    required LibraryRepository library,
    Settings? settings,
  })  : _library = library,
        _settings = settings;

  final LibraryRepository _library;
  final Settings? _settings;

  final AudioPlayer _player = AudioPlayer();

  late final PlayCounter _playCounter = PlayCounter(
    onPlay: (id) => _settings?.recordPlay(id),
  );

  final _crossfade = ValueNotifier<Duration>(Duration.zero);
  final _shuffleEnabled = ValueNotifier<bool>(false);
  final _repeat = ValueNotifier<TrollRepeat>(TrollRepeat.off);
  final _sleepRemaining = ValueNotifier<Duration?>(null);
  final _sleepAtTrackEnd = ValueNotifier<bool>(false);
  final _loop = ValueNotifier<LoopRange?>(null);
  final _errors = StreamController<String>.broadcast();

  List<Track> _playable = const [];

  Timer? _sleepTimer;
  bool _sleepFading = false;
  Timer? _fadeTimer;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fading = false;
  bool _restoring = false;
  bool _loading = false;
  bool _recovering = false;

  Stream<String> get errors => _errors.stream;
  ValueNotifier<Duration> get crossfade => _crossfade;
  ValueNotifier<bool> get shuffleEnabled => _shuffleEnabled;
  ValueNotifier<TrollRepeat> get repeat => _repeat;
  ValueNotifier<Duration?> get sleepRemaining => _sleepRemaining;

  /// Повторяемый отрезок трека; `null` — повтора нет.
  ValueNotifier<LoopRange?> get loop => _loop;

  /// Таймер сна «до конца текущего трека».
  ValueNotifier<bool> get sleepAtTrackEnd => _sleepAtTrackEnd;
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

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
    // Очередь и текущий индекс сохраняются при любом изменении.
    queue.listen((_) => _persistQueue());
    _player.currentIndexStream.listen((_) {
      _loop.value = null;
      _syncQueueIndex();
      _persistCurrentTrack();
      _persistQueue();
      if (!_restoring) _fadeIn();
    });
    _player.positionStream.listen((position) {
      _playCounter.tick(position, playing: _player.playing);
      _maybeLoop(position);
      _maybeFadeOut(position);
      _maybeSleepAtTrackEnd(position);
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
    setSkipSilence(settings.skipSilence);
  }

  /// Пропуск тишины; платформы без поддержки молча игнорируют вызов.
  Future<void> setSkipSilence(bool enabled) async {
    _settings?.skipSilence = enabled;
    try {
      await _player.setSkipSilenceEnabled(enabled);
    } catch (_) {}
  }

  Future<void> restoreLastPlayed() async {
    final settings = _settings;
    if (settings == null) return;
    // Позицию читаем до загрузки: при смене трека она сбрасывается.
    final savedPosition = Duration(milliseconds: settings.lastPositionMs);
    final lastId = settings.lastTrackId;

    bool available(String id) {
      final t = _library.trackById(id);
      return t != null && _library.isAvailable(t);
    }

    var restored = restoreQueue(
      savedIds: settings.sessionQueue,
      savedIndex: settings.sessionIndex,
      isAvailable: available,
    );
    // Старые версии хранили только последний трек.
    if (restored.ids.isEmpty && lastId != null && lastId.isNotEmpty && available(lastId)) {
      restored = (ids: [lastId], index: 0, sameTrack: true);
    }
    if (restored.ids.isEmpty) return;

    final tracks = [
      for (final id in restored.ids) _library.trackById(id)!,
    ];
    final position = restored.sameTrack && tracks[restored.index].id == lastId
        ? savedPosition
        : Duration.zero;

    _restoring = true;
    try {
      await setLibraryQueue(tracks, initialIndex: restored.index, autoPlay: false);
      if (position > Duration.zero) await _player.seek(position);
    } catch (_) {
    } finally {
      _restoring = false;
    }
  }

  AudioSource _source(Track track) => AudioSource.uri(
        Uri.file(track.localPath!),
        tag: _toMediaItem(track),
      );

  /// Оставляет только треки, чей файл на месте.
  List<Track> _available(Iterable<Track> tracks) =>
      tracks.where(_library.isAvailable).toList();

  Future<void> setLibraryQueue(
    Iterable<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    final requested = tracks.toList();
    if (requested.isEmpty) return;

    final anchor = requested[initialIndex.clamp(0, requested.length - 1)];
    final playable = _available(requested);
    var index = playable.indexWhere((t) => t.id == anchor.id);
    if (index < 0) {
      _errors.add('Файл трека не найден. Импортируйте его заново.');
      if (playable.isEmpty) return;
      index = 0;
    }

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

  /// Играть список в случайном порядке с первого трека.
  Future<void> playShuffled(Iterable<Track> tracks) async {
    final source = tracks.toList();
    if (source.isEmpty) return;

    final settings = _settings;
    final List<Track> list;
    if (settings != null && settings.smartShuffle) {
      list = smartShuffle(
        source,
        recentIds: settings.recentIds,
        playCounts: settings.playCounts,
      );
      // Порядок уже готов: режим случайного порядка плеера его перемешал бы.
      await setShuffle(false);
    } else {
      list = source..shuffle();
    }
    await setLibraryQueue(list);
  }

  Future<bool> playNext(Track track) async {
    if (!_library.isAvailable(track)) return false;

    // Очередь пуста: просто начинаем играть этот трек.
    if (_playable.isEmpty) {
      await setLibraryQueue([track]);
      return true;
    }

    final items = [...queue.value];
    final current = _player.currentIndex;
    final insertAt = current == null ? items.length : (current + 1).clamp(0, items.length);
    items.insert(insertAt, _toMediaItem(track));
    queue.add(items);

    try {
      await _player.insertAudioSource(insertAt, _source(track));
      _playable = [..._playable]..insert(insertAt.clamp(0, _playable.length), track);
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<bool> addToQueue(Track track) async {
    if (!_library.isAvailable(track)) return false;

    if (_playable.isEmpty) {
      await setLibraryQueue([track]);
      return true;
    }

    queue.add([...queue.value, _toMediaItem(track)]);
    try {
      await _player.addAudioSource(_source(track));
      _playable = [..._playable, track];
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> _load(
    List<Track> tracks,
    int index, {
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map(_source).toList();
    final target = index.clamp(0, sources.length - 1);
    _playable = tracks;
    mediaItem.add(_toMediaItem(tracks[target]));
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    _loading = true;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: target,
        initialPosition: Duration.zero,
      );
      await _player.setVolume(1);
      if (autoPlay) unawaited(play());
    } catch (error) {
      debugPrint('load: $error');
      _emitError('Не удалось открыть файл');
    } finally {
      _loading = false;
      _persistQueue();
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

    items.removeAt(index);
    if (items.isEmpty) {
      await clearQueue();
      return;
    }

    queue.add(items);
    if (index < _playable.length) {
      _playable = [..._playable]..removeAt(index);
    }
    await _player.removeAudioSourceAt(index);
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
    _loop.value = null;
    await _player.stop();
    _persistPosition(_player.position, force: true);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) {
    // Перемотка пользователем за пределы отрезка отменяет повтор.
    final range = _loop.value;
    if (range != null && !range.contains(position)) _loop.value = null;
    return _player.seek(position);
  }

  /// Зацикливает отрезок [range] и сразу запускает его с начала.
  Future<void> setLoop(LoopRange range) async {
    _loop.value = range;
    await _player.seek(range.start);
    await play();
  }

  void clearLoop() => _loop.value = null;

  void _maybeLoop(Duration position) {
    final range = _loop.value;
    if (range != null && range.reached(position)) {
      _player.seek(range.start);
    }
  }

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
    cancelSleepTimer();
    _sleepRemaining.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining =
          (_sleepRemaining.value ?? Duration.zero) - const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        timer.cancel();
        _sleepRemaining.value = null;
        _stopFaded();
      } else {
        _sleepRemaining.value = remaining;
        _applySleepFade(remaining, const Duration(seconds: 45));
      }
    });
  }

  /// Остановить воспроизведение, когда закончится текущий трек.
  void sleepAfterCurrentTrack() {
    cancelSleepTimer();
    _sleepAtTrackEnd.value = true;
  }

  /// Плавное затухание перед остановкой по таймеру сна.
  void _applySleepFade(Duration remaining, Duration fade) {
    final volume = sleepFadeVolume(remaining, fade: fade);
    if (volume >= 1 && !_sleepFading) return;
    _sleepFading = volume < 1;
    unawaited(_player.setVolume(volume));
  }

  /// Пауза после затухания; громкость возвращается, чтобы следующий
  /// запуск не был тихим.
  void _stopFaded() {
    unawaited(pause().then((_) async {
      _sleepFading = false;
      await _player.setVolume(1);
    }));
  }

  void cancelSleepTimer() {
    if (_sleepFading) {
      _sleepFading = false;
      unawaited(_player.setVolume(1));
    }
    _sleepTimer?.cancel();
    _sleepRemaining.value = null;
    _sleepAtTrackEnd.value = false;
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
    unawaited(_skipBroken());
  }

  /// Файл не читается — переходим к следующему, чтобы очередь не вставала.
  Future<void> _skipBroken() async {
    if (_recovering) return;
    _recovering = true;
    try {
      if (_player.hasNext) {
        _errors.add('Не удалось воспроизвести трек, включаю следующий');
        await _player.seekToNext();
        await play();
      } else {
        _emitError('Не удалось воспроизвести трек');
      }
    } catch (_) {
    } finally {
      _recovering = false;
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

  /// В just_audio `completed` наступает только в конце всей очереди, поэтому
  /// конец текущего трека ловим по позиции.
  void _maybeSleepAtTrackEnd(Duration position) {
    if (!_sleepAtTrackEnd.value) return;
    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    final left = duration - position;
    const fade = Duration(seconds: 20);
    if (left > const Duration(milliseconds: 400)) {
      _applySleepFade(left, fade);
      return;
    }
    _sleepAtTrackEnd.value = false;
    _stopFaded();
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
    // Пока трек не загружен или идёт восстановление, позицию не трогаем:
    // иначе нулевая позиция при старте затрёт сохранённую.
    if (_restoring || _loading || mediaItem.value == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPositionSave) < const Duration(seconds: 5)) {
      return;
    }
    _lastPositionSave = now;
    settings.lastPositionMs = position.inMilliseconds;
  }

  void _persistQueue() {
    final settings = _settings;
    if (settings == null || _loading) return;
    final ids = [for (final item in queue.value) item.id];
    // Пустую очередь (старт приложения до восстановления) не сохраняем.
    if (ids.isEmpty) return;
    final trimmed = trimQueue(ids, _player.currentIndex ?? 0);
    settings.sessionQueue = trimmed.ids;
    settings.sessionIndex = trimmed.index;
  }

  /// Сохраняет позицию сразу (приложение уходит в фон или закрывается).
  void flushSession() {
    _persistPosition(_player.position, force: true);
    _persistQueue();
  }

  void _persistCurrentTrack() {
    final settings = _settings;
    if (settings == null) return;
    final item = mediaItem.value;
    if (item == null) return;
    settings.lastTrackId = item.id;
    // Тот же трек (повторное уведомление об индексе) не обнуляет позицию и
    // не пишется заново; статистику ведёт [_playCounter]. Восстановленный
    // при старте трек тоже запоминается, но ничего не пишет.
    final isNewTrack = _playCounter.currentId != item.id;
    _playCounter.startTrack(item.id, item.duration ?? _player.duration);
    if (_restoring || !isNewTrack) return;
    settings.lastPositionMs = 0;
    settings.recordRecent(item.id);
  }

  void _onCompleted() {
    if (_sleepAtTrackEnd.value) {
      _sleepAtTrackEnd.value = false;
      _stopFaded();
      return;
    }
    if (_repeat.value == TrollRepeat.one) {
      _playCounter.restart();
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
      );

  Uri? _artUri(Track track) {
    final path = track.artworkPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Uri.file(path);
    }
    return null;
  }
}
