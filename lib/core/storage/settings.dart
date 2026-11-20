import 'package:hive_flutter/hive_flutter.dart';

import '../config/app_config.dart';

class Settings {
  Settings(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  static Future<Settings> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<dynamic>(boxName);
    return Settings(box);
  }

  String get workerUrl =>
      (_box.get('workerUrl') as String?)?.trim().isNotEmpty == true
          ? (_box.get('workerUrl') as String).trim()
          : AppConfig.defaultWorkerUrl;

  set workerUrl(String value) => _box.put('workerUrl', value.trim());

  bool get useWorkerProxy => _box.get('useWorkerProxy', defaultValue: true) as bool;

  set useWorkerProxy(bool value) => _box.put('useWorkerProxy', value);

  List<String> get pipedInstances =>
      (_box.get('pipedInstances') as List?)?.cast<String>().toList() ??
      AppConfig.defaultPipedInstances;

  set pipedInstances(List<String> value) => _box.put('pipedInstances', value);

  List<String> get invidiousInstances =>
      (_box.get('invidiousInstances') as List?)?.cast<String>().toList() ??
      AppConfig.defaultInvidiousInstances;

  set invidiousInstances(List<String> value) =>
      _box.put('invidiousInstances', value);

  String get spotifyClientId => _box.get('spotifyClientId') as String? ?? '';

  set spotifyClientId(String value) => _box.put('spotifyClientId', value.trim());

  String get spotifyClientSecret =>
      _box.get('spotifyClientSecret') as String? ?? '';

  set spotifyClientSecret(String value) =>
      _box.put('spotifyClientSecret', value.trim());

  int get bitrate => _box.get('bitrate', defaultValue: AppConfig.defaultBitrate) as int;

  set bitrate(int value) => _box.put('bitrate', value);

  bool get preferOpus => _box.get('preferOpus', defaultValue: false) as bool;

  set preferOpus(bool value) => _box.put('preferOpus', value);

  bool get proxyAudioStreams =>
      _box.get('proxyAudioStreams', defaultValue: true) as bool;

  set proxyAudioStreams(bool value) => _box.put('proxyAudioStreams', value);
}
