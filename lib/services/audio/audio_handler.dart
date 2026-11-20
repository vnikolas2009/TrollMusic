import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';

enum YsRepeat { off, all, one }

class YsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  YsAudioHandler({required LibraryRepository library}) : _library = library;

  final LibraryRepository _library;
  final AudioPlayer _player = AudioPlayer();

  final _crossfade = ValueNotifier<Duration>(Duration.zero);
  final _shuffleEnabled = ValueNotifier<bool>(false);
  final _repeat = ValueNotifier<YsRepeat>(YsRepeat.off);
  final _sleepRemaining = ValueNotifier<Duration?>(null);

  Timer? _sleepTimer;

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
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stack) => debugPrint('$error'),
    );
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.currentIndexStream.listen((_) => _syncQueueIndex());
  }

  Future<void> setLibraryQueue(Iterable<Track> tracks, {int initialIndex = 0}) async {
    final list = tracks.toList();
    if (list.isEmpty) return;
    queue.add(list.map(_toMediaItem).toList());
    await _load(list, initialIndex.clamp(0, list.length - 1));
  }

  Future<void> playTrack(Track track, {List<Track>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((t) => t.id == track.id);
      await setLibraryQueue(contextQueue, initialIndex: index < 0 ? 0 : index);
      return;
    }
    await setLibraryQueue([track]);
  }

  Future<void> _load(List<Track> tracks, int index) async {
    final playable = tracks.where((t) {
      final source = t.localPath ?? t.streamUrl;
      return source != null && source.isNotEmpty;
    }).toList();
    if (playable.isEmpty) return;

    final items = playable
        .map((t) => AudioSource.uri(
              Uri.parse(t.localPath ?? t.streamUrl!),
              tag: _toMediaItem(t),
            ))
        .toList();
    mediaItem.add(items[index.clamp(0, items.length - 1)].tag as MediaItem);
    await _player.setAudioSources(
      items,
      initialIndex: index.clamp(0, items.length - 1),
      initialPosition: Duration.zero,
    );
    play();
  }

  Future<void> playAt(int index) async {
    final sequence = _player.sequenceState.sequence;
    if (index < 0 || index >= sequence.length) return;
    await _player.seek(Duration.zero, index: index);
    play();
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

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (!_player.hasNext) {
      if (_repeat.value == YsRepeat.all) {
        await _player.seek(Duration.zero, index: 0);
        play();
      }
      return;
    }
    await _player.seekToNext();
    play();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
      return;
    }
    await _player.seekToPrevious();
    play();
  }

  Future<void> setShuffle(bool enabled) async {
    _shuffleEnabled.value = enabled;
    await _player.setShuffleModeEnabled(enabled);
    if (enabled) await _player.shuffle();
  }

  Future<void> cycleRepeat() async {
    final next = switch (_repeat.value) {
      YsRepeat.off => YsRepeat.all,
      YsRepeat.all => YsRepeat.one,
      YsRepeat.one => YsRepeat.off,
    };
    _repeat.value = next;
    await _player.setLoopMode(switch (next) {
      YsRepeat.off => LoopMode.off,
      YsRepeat.all => LoopMode.all,
      YsRepeat.one => LoopMode.one,
    });
  }

  Future<void> setCrossfade(Duration value) async {
    _crossfade.value = value;
  }

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepRemaining.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = (_sleepRemaining.value ?? Duration.zero) - const Duration(seconds: 1);
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
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Lyrics? lyricsForCurrent() {
    final item = mediaItem.value;
    if (item == null) return null;
    final raw = _library.lyricsFor(item.id);
    return raw == null ? null : LrcParser.parse(raw);
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
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
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
