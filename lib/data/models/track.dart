enum TrackSource { youtube, spotify, soundcloud, local, downloaded }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = Duration.zero,
    this.thumbnailUrl,
    this.streamUrl,
    this.localPath,
    this.lyricsPath,
    this.artworkPath,
    this.explicit = false,
    this.source = TrackSource.youtube,
    this.bitrate,
    this.albumId,
    this.sourcePath,
    this.sourceSize,
    this.sourceModifiedAtMs,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? thumbnailUrl;
  final String? streamUrl;
  final String? localPath;
  final String? lyricsPath;
  final String? artworkPath;
  final bool explicit;
  final TrackSource source;
  final int? bitrate;
  final String? albumId;

  /// Исходный путь файла, из которого импортирован трек.
  final String? sourcePath;

  /// Размер исходного файла в байтах.
  final int? sourceSize;

  /// Время последнего изменения исходного файла.
  final int? sourceModifiedAtMs;

  bool get isOffline => localPath != null;

  String get displaySubtitle => explicit ? 'E · $artist' : artist;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? thumbnailUrl,
    String? streamUrl,
    String? localPath,
    String? lyricsPath,
    String? artworkPath,
    bool? explicit,
    TrackSource? source,
    int? bitrate,
    String? albumId,
    String? sourcePath,
    int? sourceSize,
    int? sourceModifiedAtMs,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      localPath: localPath ?? this.localPath,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      artworkPath: artworkPath ?? this.artworkPath,
      explicit: explicit ?? this.explicit,
      source: source ?? this.source,
      bitrate: bitrate ?? this.bitrate,
      albumId: albumId ?? this.albumId,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceSize: sourceSize ?? this.sourceSize,
      sourceModifiedAtMs:
          sourceModifiedAtMs ?? this.sourceModifiedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration.inMilliseconds,
        'thumbnailUrl': thumbnailUrl,
        'streamUrl': streamUrl,
        'localPath': localPath,
        'lyricsPath': lyricsPath,
        'artworkPath': artworkPath,
        'explicit': explicit,
        'source': source.name,
        'bitrate': bitrate,
        'albumId': albumId,
        'sourcePath': sourcePath,
        'sourceSize': sourceSize,
        'sourceModifiedAtMs': sourceModifiedAtMs,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        duration: Duration(
          milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
        ),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        streamUrl: json['streamUrl'] as String?,
        localPath: json['localPath'] as String?,
        lyricsPath: json['lyricsPath'] as String?,
        artworkPath: json['artworkPath'] as String?,
        explicit: json['explicit'] as bool? ?? false,
        source: TrackSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => TrackSource.youtube,
        ),
        bitrate: (json['bitrate'] as num?)?.toInt(),
        albumId: json['albumId'] as String?,
        sourcePath: json['sourcePath'] as String?,
        sourceSize: (json['sourceSize'] as num?)?.toInt(),
        sourceModifiedAtMs:
            (json['sourceModifiedAtMs'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
