/// Приводит ввод пользователя к виду `host:port` для HTTP-прокси.
/// Возвращает пустую строку, если адрес некорректен или это SOCKS
/// (dart:io поддерживает только HTTP CONNECT).
String normalizeProxyAddress(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  final lower = value.toLowerCase();
  if (lower.startsWith('socks')) return '';

  value = value.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  value = value.split('/').first;
  if (value.contains('@')) value = value.split('@').last;

  final match = RegExp(r'^([A-Za-z0-9.\-]+):(\d{1,5})$').firstMatch(value);
  if (match == null) return '';
  final port = int.parse(match.group(2)!);
  if (port < 1 || port > 65535) return '';
  return '${match.group(1)}:$port';
}
