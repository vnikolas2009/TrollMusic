import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/models/track.dart';
import 'network_providers.dart';

/// Источник каталога на главной и в поиске.
///
/// Порядок значений менять нельзя: в настройках хранится индекс
/// (`Settings.musicSourceIndex`), новые источники добавляются в конец.
enum MusicSource {
  spotify('Spotify', Color(0xFF1ED760)),
  youtube('YouTube Music', Color(0xFFFF3B30)),
  yandex('Яндекс Музыка', Color(0xFFFFCC00)),
  vk('VK Музыка', Color(0xFF2787F5)),
  audius('Audius', Color(0xFFCC0FE0));

  const MusicSource(this.label, this.color);

  final String label;

  /// Фирменный цвет источника (точка в переключателе).
  final Color color;
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

/// Токены пользователя для Яндекс Музыки и VK. Хранятся в `Settings`;
/// провайдер нужен, чтобы экраны перестраивались сразу после ввода токена.
class ServiceTokens {
  const ServiceTokens({this.yandex = '', this.vk = ''});

  final String yandex;
  final String vk;

  bool get hasYandex => yandex.isNotEmpty;
  bool get hasVk => vk.isNotEmpty;
}

class ServiceTokensController extends Notifier<ServiceTokens> {
  @override
  ServiceTokens build() {
    final settings = ref.read(settingsProvider);
    return ServiceTokens(yandex: settings.yandexToken, vk: settings.vkToken);
  }

  void setYandex(String value) {
    final settings = ref.read(settingsProvider);
    settings.yandexToken = value;
    state = ServiceTokens(yandex: settings.yandexToken, vk: state.vk);
  }

  void setVk(String value) {
    final settings = ref.read(settingsProvider);
    settings.vkToken = value;
    state = ServiceTokens(yandex: state.yandex, vk: settings.vkToken);
  }
}

final serviceTokensProvider =
    NotifierProvider<ServiceTokensController, ServiceTokens>(
      ServiceTokensController.new,
    );

/// Чарт Яндекс Музыки (при недоступности — подборка по запросам).
final yandexTrendingProvider = FutureProvider<List<Track>>((ref) async {
  return ref.watch(musicRepositoryProvider).yandexTrending();
});

/// Подборка VK Музыки. Без токена не обращается к сети и возвращает пустой
/// список; после ввода токена перезагружается автоматически.
final vkTrendingProvider = FutureProvider<List<Track>>((ref) async {
  final tokens = ref.watch(serviceTokensProvider);
  if (!tokens.hasVk) return const <Track>[];
  return ref.watch(musicRepositoryProvider).vkMix(AppConfig.vkQueries);
});

/// Тренды Audius за неделю.
final audiusTrendingProvider = FutureProvider<List<Track>>((ref) async {
  return ref.watch(musicRepositoryProvider).audiusTrending();
});
