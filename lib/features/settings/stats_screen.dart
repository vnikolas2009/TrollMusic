import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/play_stats.dart';
import '../../shared/widgets/cover_art.dart';

enum _Period {
  week('Неделя', Duration(days: 7)),
  month('Месяц', Duration(days: 30)),
  all('Всё записанное', null);

  const _Period(this.label, this.span);
  final String label;
  final Duration? span;
}

/// Статистика прослушиваний: количество, оценка времени, топ треков и
/// исполнителей за неделю, месяц или весь журнал (последние 3000 прослушиваний).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _Period _period = _Period.week;

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m мин';
    return '$h ч $m мин';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final tracks = {for (final t in ref.watch(libraryProvider).tracks) t.id: t};

    final span = _period.span;
    final stats = computeStats(
      cleanPlayLog(parsePlayLog(settings.playLog)),
      tracks,
      since: span == null ? null : DateTime.now().subtract(span),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final p in _Period.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: p == _period,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Figure(value: '${stats.plays}', label: 'прослушиваний')),
              const SizedBox(width: 12),
              Expanded(child: _Figure(value: _duration(stats.listened), label: 'примерно в эфире')),
            ],
          ),
          if (stats.plays == 0)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'За этот период прослушиваний нет.\nСтатистика копится с момента этого обновления.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            const _Heading('Топ треков'),
            for (final (index, item) in stats.topTracks.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CoverArt(path: item.track.artworkPath, size: 44, radius: 10),
                title: Text('${index + 1}. ${item.track.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${item.plays}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            const _Heading('Топ исполнителей'),
            for (final (index, item) in stats.topArtists.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${index + 1}. ${item.artist}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${item.plays}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.accent),
      ),
    );
  }
}
