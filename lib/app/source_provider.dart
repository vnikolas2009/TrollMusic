import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_providers.dart';

/// Источник каталога: YouTube Music и Spotify показываются раздельно.
enum MusicSource {
  spotify('Spotify'),
  youtube('YouTube Music');

  const MusicSource(this.label);
  final String label;
}

class MusicSourceController extends Notifier<MusicSource> {
  @override
  MusicSource build() {
    final i = ref.read(settingsProvider).musicSourceIndex;
    return MusicSource.values[i.clamp(0, MusicSource.values.length - 1)];
  }

  void select(MusicSource source) {
    if (source == state) return;
    ref.read(settingsProvider).musicSourceIndex = source.index;
    state = source;
  }
}

final musicSourceProvider =
    NotifierProvider<MusicSourceController, MusicSource>(MusicSourceController.new);
