/// Прямая ссылка на аудиопоток вместе с заголовками, с которыми её выдали.
///
/// Ссылки googlevideo привязаны к клиенту (User-Agent) и быстро протухают,
/// поэтому их нельзя хранить в библиотеке — только получать перед воспроизведением.
class StreamCandidate {
  const StreamCandidate({
    required this.url,
    required this.userAgent,
    this.mime = '',
    this.kbps = 0,
    this.loudnessDb,
  });

  final String url;
  final String userAgent;
  final String mime;
  final int kbps;
  final double? loudnessDb;

  Map<String, String> get headers => {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      };

  String get extension {
    final m = mime.toLowerCase();
    if (m.contains('webm') || m.contains('opus')) return 'opus';
    if (m.contains('mp4') || m.contains('m4a')) return 'm4a';
    final uri = Uri.tryParse(url);
    final fromUrl = (uri?.queryParameters['mime'] ?? '').toLowerCase();
    if (fromUrl.contains('webm') || fromUrl.contains('opus')) return 'opus';
    return 'm4a';
  }
}
