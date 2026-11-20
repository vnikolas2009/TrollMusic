enum SpotifyKind { playlist, album, track }

class SpotifyLink {
  const SpotifyLink(this.kind, this.id);

  final SpotifyKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is SpotifyLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

final _uriForm = RegExp(r'spotify:(playlist|album|track):([A-Za-z0-9]{10,})');
final _webForm = RegExp(
  r'open\.spotify\.com/(?:intl-[a-z-]+/)?(?:embed/)?(playlist|album|track)/([A-Za-z0-9]+)',
);

/// Разбирает ссылку, URI или «голый» 22-символьный id Spotify.
SpotifyLink? parseSpotifyLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final match = _uriForm.firstMatch(text) ?? _webForm.firstMatch(text);
  if (match != null) {
    return SpotifyLink(SpotifyKind.values.byName(match.group(1)!), match.group(2)!);
  }
  if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(text)) {
    return SpotifyLink(SpotifyKind.playlist, text);
  }
  return null;
}
