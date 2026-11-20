String formatDuration(Duration? d) {
  if (d == null) return '0:00';
  final total = d.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '$hours:${rest.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatLongDuration(Duration? d) {
  if (d == null || d == Duration.zero) return '—';
  final total = d.inMinutes;
  final hours = total ~/ 60;
  final minutes = total % 60;
  if (hours > 0) return '$hours ч $minutes мин';
  return '$minutes мин';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 МБ';
  const units = ['Б', 'КБ', 'МБ', 'ГБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatCount(int? value) {
  if (value == null) return '';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} млн';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} тыс.';
  return '$value';
}
