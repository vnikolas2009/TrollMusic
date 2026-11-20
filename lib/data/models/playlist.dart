import 'track.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.tracks = const [],
    this.ownerName,
    this.isRadio = false,
    this.colorValue,
  });

  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final List<Track> tracks;
  final String? ownerName;
  final bool isRadio;
  final int? colorValue;

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    List<Track>? tracks,
    String? ownerName,
    bool? isRadio,
    int? colorValue,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      tracks: tracks ?? this.tracks,
      ownerName: ownerName ?? this.ownerName,
      isRadio: isRadio ?? this.isRadio,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'ownerName': ownerName,
        'isRadio': isRadio,
        'colorValue': colorValue,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        tracks: (json['tracks'] as List<dynamic>? ?? [])
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList(),
        ownerName: json['ownerName'] as String?,
        isRadio: json['isRadio'] as bool? ?? false,
        colorValue: (json['colorValue'] as num?)?.toInt(),
      );
}
