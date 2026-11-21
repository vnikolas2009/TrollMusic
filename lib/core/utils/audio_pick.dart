import 'dart:math' as math;

/// Качество звука, которое выбирает пользователь.
enum AudioQuality { low, medium, high, auto }

/// Аудиоформат, из которых выбирается поток (чистая модель без сети).
class AudioFormat {
  const AudioFormat({
    required this.url,
    required this.mime,
    required this.kbps,
    this.loudnessDb,
  });

  final String url;
  final String mime;
  final int kbps;
  final double? loudnessDb;

  bool get isAac {
    final m = mime.toLowerCase();
    return m.contains('mp4') || m.contains('m4a') || m.contains('aac');
  }

  bool get isOpus {
    final m = mime.toLowerCase();
    return m.contains('opus') || m.contains('webm');
  }
}

/// Целевой битрейт в kbps; `null` — максимально доступное качество.
int? targetKbps(AudioQuality quality, {required bool onWifi}) {
  switch (quality) {
    case AudioQuality.low:
      return 64;
    case AudioQuality.medium:
      return 128;
    case AudioQuality.high:
      return null;
    case AudioQuality.auto:
      return onWifi ? null : 128;
  }
}

/// Сортирует форматы по близости к выбранному качеству.
///
/// [aacOnly] нужен на iOS: AVPlayer не играет WebM/Opus.
List<AudioFormat> rankFormats(
  Iterable<AudioFormat> formats, {
  required AudioQuality quality,
  required bool onWifi,
  bool aacOnly = false,
  int limit = 3,
}) {
  final target = targetKbps(quality, onWifi: onWifi);
  final list = [
    for (final f in formats)
      if (f.url.isNotEmpty && (!aacOnly || f.isAac)) f,
  ];

  int score(AudioFormat f) {
    final base = target == null ? f.kbps * 4 : -((f.kbps - target).abs()) * 4;
    return base + (f.isAac ? 30 : 0);
  }

  list.sort((a, b) => score(b).compareTo(score(a)));
  return list.take(limit).toList();
}

/// Разбор заголовка `Content-Range: bytes 0-99/1000`.
({int start, int end, int? total})? parseContentRange(String? header) {
  if (header == null) return null;
  final match = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(header);
  if (match == null) return null;
  final total = match.group(3)!;
  return (
    start: int.parse(match.group(1)!),
    end: int.parse(match.group(2)!),
    total: total == '*' ? null : int.parse(total),
  );
}

/// Множитель громкости для нормализации. YouTube отдаёт `loudnessDb`
/// относительно эталона: положительное значение — трек громче эталона.
/// Усиливать нельзя, поэтому результат всегда в диапазоне 0.25–1.0.
double loudnessGain(double? loudnessDb) {
  if (loudnessDb == null || loudnessDb <= 0) return 1.0;
  final gain = math.pow(10, -loudnessDb / 20).toDouble();
  return gain.clamp(0.25, 1.0).toDouble();
}
