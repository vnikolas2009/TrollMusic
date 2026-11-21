import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/source_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/section_header.dart';
import '../playlist/playlist_screen.dart';

/// Подборка по настроению или жанру: набор поисковых запросов к YouTube Music.
class MoodMix {
  const MoodMix(this.id, this.title, this.icon, this.queries);

  final String id;
  final String title;
  final IconData icon;
  final List<String> queries;
}

const moodMixes = <MoodMix>[
  MoodMix('chill', 'Чилл', Icons.spa_outlined,
      ['chill vibes songs', 'lofi chill music', 'чилл русские песни']),
  MoodMix('workout', 'Тренировка', Icons.fitness_center,
      ['workout music hits', 'gym motivation songs', 'спорт музыка']),
  MoodMix('focus', 'Фокус', Icons.center_focus_strong_outlined,
      ['focus music instrumental', 'deep work lofi', 'concentration music']),
  MoodMix('party', 'Вечеринка', Icons.celebration_outlined,
      ['party hits', 'dance hits 2026', 'клубная музыка хиты']),
  MoodMix('sleep', 'Сон', Icons.nightlight_outlined,
      ['sleep music calm', 'relaxing piano', 'ambient sleep']),
  MoodMix('love', 'Романтика', Icons.favorite_border,
      ['romantic songs', 'love songs hits', 'песни о любви']),
  MoodMix('hiphop', 'Хип-хоп', Icons.mic_external_on_outlined,
      ['hip hop hits', 'русский рэп хиты', 'rap new']),
  MoodMix('rock', 'Рок', Icons.electric_bolt,
      ['rock hits', 'classic rock songs', 'русский рок']),
  MoodMix('electronic', 'Электроника', Icons.graphic_eq,
      ['electronic music hits', 'house music', 'synthwave']),
  MoodMix('pop', 'Поп', Icons.star_outline,
      ['pop hits 2026', 'русская поп музыка', 'k-pop hits']),
  MoodMix('jazz', 'Джаз', Icons.piano_outlined,
      ['jazz classics', 'smooth jazz', 'jazz lounge']),
  MoodMix('classical', 'Классика', Icons.library_music_outlined,
      ['classical music best', 'piano classical', 'orchestra masterpieces']),
];

/// Ключ — `youtube:chill` / `spotify:chill`.
final moodTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, key) async {
  final parts = key.split(':');
  final mood = moodMixes.firstWhere((m) => m.id == parts.last);
  if (parts.first == MusicSource.spotify.name) {
    return ref.watch(musicRepositoryProvider).spotifyMix(mood.queries, limit: 30);
  }
  return ref.watch(youtubeClientProvider).mix(mood.queries, limit: 30);
});

/// Горизонтальная лента «Настроение и жанры».
class MoodSection extends ConsumerWidget {
  const MoodSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(musicSourceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Настроение и жанры',
          subtitle: 'Подборки только из музыки',
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: moodMixes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final mood = moodMixes[i];
              return PressScale(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MoodScreen(mood: mood, source: source),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(mood.icon, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        mood.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Экран подборки: загружает треки и открывает обычный экран плейлиста.
class MoodScreen extends ConsumerWidget {
  const MoodScreen({super.key, required this.mood, required this.source});

  final MoodMix mood;
  final MusicSource source;

  String get _key => '${source.name}:${mood.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(moodTracksProvider(_key));
    return tracks.when(
      data: (items) {
        if (items.isEmpty) return _Message(mood: mood, retry: ref, keyName: _key);
        return PlaylistScreen(
          id: 'mood:${source.name}:${mood.id}',
          title: mood.title,
          subtitle: '${source.label} · ${items.length} треков',
          tracks: items,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(mood.title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _Message(mood: mood, retry: ref, keyName: _key),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.mood, required this.retry, required this.keyName});

  final MoodMix mood;
  final WidgetRef retry;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(mood.title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Не удалось загрузить подборку',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => retry.invalidate(moodTracksProvider(keyName)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
