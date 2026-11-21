import 'dart:io';

DateTime _checkedAt = DateTime.fromMillisecondsSinceEpoch(0);
bool _lastWifi = true;

/// Грубое определение «мы на Wi‑Fi» без внешних плагинов (по имени интерфейса).
///
/// Android: `wlan0`; iOS: `en0` (мобильная сеть там `pdp_ip0`). Если
/// определить нельзя — считаем, что Wi‑Fi, чтобы не занижать качество.
Future<bool> isOnWifi() async {
  final now = DateTime.now();
  if (now.difference(_checkedAt) < const Duration(seconds: 15)) return _lastWifi;
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    var wifi = false;
    for (final item in interfaces) {
      final name = item.name.toLowerCase();
      if (name.startsWith('wlan') || name == 'en0' || name.startsWith('eth')) {
        wifi = true;
      }
    }
    _lastWifi = wifi;
  } catch (_) {
    _lastWifi = true;
  }
  _checkedAt = now;
  return _lastWifi;
}
