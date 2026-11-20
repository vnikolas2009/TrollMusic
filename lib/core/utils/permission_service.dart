import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

abstract final class PermissionService {
  static Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  static Future<bool> requestAudioFiles() async {
    if (!Platform.isAndroid) return true;
    final audio = await Permission.audio.status;
    if (audio.isGranted) return true;
    final result = await Permission.audio.request();
    return result.isGranted;
  }
}
