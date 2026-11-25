import 'track.dart';

/// Пользовательский плейлист. Лишние поля старых версий при чтении игнорируются.
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.description = '',
    this.tracks = const [],
    this.colorValue,
  });

  final String id;
  final String title;
  final String description;
  final List<Track> tracks;
  final int? colorValue;

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  Playlist copyWith({
    String? title,
    String? description,
    List<Track>? tracks,
    int? colorValue,
  }) {
    return Playlist(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      tracks: tracks ?? this.tracks,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'colorValue': colorValue,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList(),
        colorValue: (json['colorValue'] as num?)?.toInt(),
      );
}
