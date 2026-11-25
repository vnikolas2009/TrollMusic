/// Подставляется, когда в тегах нет исполнителя.
const unknownArtist = 'Неизвестный исполнитель';

/// Локальный трек. Все треки лежат в хранилище приложения на устройстве.
///
/// Старые записи (когда в приложении были стриминговые источники) читаются
/// без ошибок: лишние ключи JSON просто игнорируются.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = Duration.zero,
    this.localPath,
    this.lyricsPath,
    this.artworkPath,
    this.explicit = false,
    this.bitrate,
    this.addedAtMs,
    this.sourcePath,
    this.sourceSize,
    this.sourceModifiedAtMs,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? localPath;
  final String? lyricsPath;
  final String? artworkPath;
  final bool explicit;
  final int? bitrate;

  /// Когда трек добавлен в медиатеку (мс с эпохи). У старых записей `null`.
  final int? addedAtMs;

  /// Исходный путь файла, из которого импортирован трек.
  final String? sourcePath;

  /// Размер исходного файла в байтах.
  final int? sourceSize;

  /// Время последнего изменения исходного файла.
  final int? sourceModifiedAtMs;

  String get displaySubtitle => explicit ? 'E · $artist' : artist;

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? localPath,
    String? lyricsPath,
    String? artworkPath,
    bool? explicit,
    int? bitrate,
    int? addedAtMs,
    String? sourcePath,
    int? sourceSize,
    int? sourceModifiedAtMs,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      localPath: localPath ?? this.localPath,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      artworkPath: artworkPath ?? this.artworkPath,
      explicit: explicit ?? this.explicit,
      bitrate: bitrate ?? this.bitrate,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceSize: sourceSize ?? this.sourceSize,
      sourceModifiedAtMs: sourceModifiedAtMs ?? this.sourceModifiedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration.inMilliseconds,
        'localPath': localPath,
        'lyricsPath': lyricsPath,
        'artworkPath': artworkPath,
        'explicit': explicit,
        'bitrate': bitrate,
        'addedAtMs': addedAtMs,
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
        localPath: json['localPath'] as String?,
        lyricsPath: json['lyricsPath'] as String?,
        artworkPath: json['artworkPath'] as String?,
        explicit: json['explicit'] as bool? ?? false,
        bitrate: (json['bitrate'] as num?)?.toInt(),
        addedAtMs: (json['addedAtMs'] as num?)?.toInt(),
        sourcePath: json['sourcePath'] as String?,
        sourceSize: (json['sourceSize'] as num?)?.toInt(),
        sourceModifiedAtMs: (json['sourceModifiedAtMs'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
