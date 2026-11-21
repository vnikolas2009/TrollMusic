import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class LibraryRepository {
  LibraryRepository._(this._tracks, this._playlists, this._lyrics);

  final Box<dynamic> _tracks;
  final Box<dynamic> _playlists;
  final Box<dynamic> _lyrics;

  final _trackUpdates = StreamController<void>.broadcast();
  final _playlistUpdates = StreamController<void>.broadcast();

  static Future<LibraryRepository> open() async {
    final tracks = await Hive.openBox<dynamic>('tracks');
    final playlists = await Hive.openBox<dynamic>('playlists');
    final lyrics = await Hive.openBox<dynamic>('lyrics');
    return LibraryRepository._(tracks, playlists, lyrics);
  }

  Stream<List<Track>> get tracksStream async* {
    yield tracks;
    yield* _trackUpdates.stream.map((_) => tracks);
  }

  Stream<List<Playlist>> get playlistsStream async* {
    yield playlists;
    yield* _playlistUpdates.stream.map((_) => playlists);
  }

  List<Track> get tracks => _decodeTracks();
  List<Track> get downloaded => tracks
      .where((t) =>
          t.source != TrackSource.local &&
          t.localPath != null &&
          t.localPath!.isNotEmpty &&
          File(t.localPath!).existsSync())
      .toList();
  List<Track> get local => tracks.where((t) => t.source == TrackSource.local).toList();

  Track? trackById(String id) {
    final raw = _tracks.get(id);
    return raw is Map ? Track.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  Future<void> saveTrack(Track track) async {
    await _tracks.put(track.id, track.toJson());
    _trackUpdates.add(null);
  }

  Future<void> saveTracks(Iterable<Track> items) async {
    await _tracks.putAll({for (final t in items) t.id: t.toJson()});
    _trackUpdates.add(null);
  }

  Future<void> deleteTrack(String id) async {
    await _tracks.delete(id);
    await _lyrics.delete(id);
    _trackUpdates.add(null);
  }

  Future<void> updateMetadata(
    String id, {
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
  }) async {
    final existing = trackById(id);
    if (existing == null) return;
    await saveTrack(existing.copyWith(
      title: title,
      artist: artist,
      album: album,
      artworkPath: artworkPath,
    ));
  }

  Set<String> get _likedIds =>
      (_tracks.get('#liked') as List?)?.cast<String>().toSet() ?? <String>{};

  bool isLiked(String id) => _likedIds.contains(id);

  List<Track> get liked => _likedIds.map(trackById).whereType<Track>().toList();

  Future<void> toggleLike(String id) async {
    final ids = _likedIds;
    if (!ids.remove(id)) ids.add(id);
    await _tracks.put('#liked', ids.toList());
    _trackUpdates.add(null);
  }

  List<Playlist> get playlists => _playlists.values
      .whereType<Map>()
      .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Playlist? playlistById(String id) {
    final raw = _playlists.get(id);
    return raw is Map ? Playlist.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  Future<void> savePlaylist(Playlist playlist) async {
    await _playlists.put(playlist.id, playlist.toJson());
    _playlistUpdates.add(null);
  }

  Future<void> deletePlaylist(String id) async {
    await _playlists.delete(id);
    _playlistUpdates.add(null);
  }

  String? lyricsFor(String trackId) => _lyrics.get(trackId) as String?;

  bool hasLyrics(String trackId) {
    final raw = _lyrics.get(trackId) as String?;
    return raw != null && raw.trim().isNotEmpty;
  }

  Future<void> saveLyrics(String trackId, String lrc) async {
    await _lyrics.put(trackId, lrc);
    final track = trackById(trackId);
    if (track == null) return;
    final path = track.lyricsPath;
    if (path != null && path.isNotEmpty) {
      await File(path).writeAsString(lrc, flush: true);
    }
  }

  Future<void> clearLyrics(String trackId) => _lyrics.delete(trackId);

  Map<String, dynamic> exportJson() => {
        'app': 'TrollMusic',
        'version': 1,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'liked': _likedIds.toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'lyrics': {for (final key in _lyrics.keys) key: _lyrics.get(key)},
      };

  Future<void> importJson(Map<String, dynamic> data) async {
    final incoming = (data['tracks'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    await saveTracks(incoming);

    final likedIds = (data['liked'] as List? ?? const []).cast<String>();
    if (likedIds.isNotEmpty) {
      await _tracks.put('#liked', {..._likedIds, ...likedIds}.toList());
    }

    final incomingPlaylists = (data['playlists'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)));
    for (final playlist in incomingPlaylists) {
      await savePlaylist(playlist);
    }

    final incomingLyrics = (data['lyrics'] as Map?) ?? const {};
    for (final entry in incomingLyrics.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        await _lyrics.put('${entry.key}', value);
      }
    }
    _trackUpdates.add(null);
  }

  List<Track> _decodeTracks() => _tracks.keys
      .where((k) => !'$k'.startsWith('#'))
      .map((k) => _tracks.get(k))
      .whereType<Map>()
      .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}
