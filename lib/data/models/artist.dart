class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.subscribers,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final int? subscribers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'subscribers': subscribers,
      };

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        subscribers: (json['subscribers'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) => other is Artist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
