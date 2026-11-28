import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lyrics_job.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/permission_service.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/tab_header.dart';
import '../../shared/widgets/track_tile.dart';
import '../browser/web_browser_screen.dart';
import 'backup_screen.dart';
import 'track_edit_sheet.dart';

/// Вкладка импорта: файлы, папки, тексты, резервная копия.
class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  bool _busy = false;

  void _say(String message, {int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: seconds)),
    );
  }

  /// Запускает поиск текстов для свежих треков, если это включено в настройках.
  void _autoLyrics(Iterable<Track> tracks) {
    if (!ref.read(settingsProvider).autoLyrics) return;
    final list = tracks.toList();
    if (list.isEmpty) return;
    ref.read(lyricsJobProvider.notifier).run(list);
  }

  Future<void> _run(Future<void> Function() action, String errorPrefix) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say('$errorPrefix: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
        await PermissionService.requestAudioFiles();
        if (!mounted) return;
        final result = await ref.read(importProvider).pickAndImport();
        if (result.tracks.isEmpty && result.lyricsAttached == 0) {
          _say('Файлы не выбраны');
          return;
        }
        _say([
          'Импортировано треков: ${result.tracks.length}',
          if (result.lyricsAttached > 0) 'текстов: ${result.lyricsAttached}',
        ].join(' · '));
        _autoLyrics(result.tracks);
      }, 'Ошибка импорта');

  bool _coversRunning = false;
  bool _coversCancel = false;
  int _coversDone = 0;
  int _coversTotal = 0;
  int _coversFound = 0;

  /// Поиск обложек в интернете для всех треков без обложки.
  Future<void> _findAllCovers() async {
    if (_coversRunning) {
      _coversCancel = true;
      return;
    }
    setState(() {
      _coversRunning = true;
      _coversCancel = false;
      _coversDone = 0;
      _coversTotal = 0;
      _coversFound = 0;
    });
    int found = 0;
    try {
      found = await ref.read(importProvider).findMissingArtwork(
        isCancelled: () => _coversCancel || !mounted,
        onProgress: (done, total, hit) {
          if (!mounted) return;
          setState(() {
            _coversDone = done;
            _coversTotal = total;
            _coversFound = hit;
          });
        },
      );
    } catch (e) {
      _say('Ошибка поиска обложек: $e');
    }
    final total = _coversTotal;
    final cancelled = _coversCancel;
    if (mounted) setState(() => _coversRunning = false);
    if (total == 0 && !cancelled) {
      _say('У всех треков уже есть обложка');
    } else {
      _say('${cancelled ? 'Остановлено. ' : ''}Найдено обложек: $found из $total', seconds: 6);
    }
  }

  void _openBrowser() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WebBrowserScreen()),
    );
  }

  void _openBackup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final library = ref.watch(libraryProvider);
    final job = ref.watch(lyricsJobProvider);
    final jobCtl = ref.read(lyricsJobProvider.notifier);

    final missing = tracks.where((t) => !library.hasLyrics(t.id)).length;

    final recent = [...tracks]
      ..sort((a, b) => (b.addedAtMs ?? 0).compareTo(a.addedAtMs ?? 0));
    final shown = recent.take(30).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverToBoxAdapter(child: TabHeader(title: 'Импорт')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(
                  index: 0,
                  child: _ActionCard(
                    icon: Icons.travel_explore_rounded,
                    title: 'Поиск треков в интернете',
                    subtitle: 'Встроенный браузер: включите трек на сайте — '
                        'плеер предложит скачать (прямые аудиофайлы)',
                    onTap: _openBrowser,
                    busy: false,
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 0,
                  child: _ActionCard(
                    icon: Icons.upload_file_rounded,
                    title: 'Файлы: аудио и тексты',
                    subtitle: 'Отметьте треки и .lrc вместе — тексты '
                        'привяжутся по названию файла',
                    onTap: _busy ? null : _import,
                    busy: _busy,
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 1,
                  child: _ActionCard(
                    icon: Icons.image_search_rounded,
                    title: _coversRunning
                        ? 'Ищу обложки: $_coversDone из $_coversTotal'
                        : 'Найти все обложки',
                    subtitle: _coversRunning
                        ? 'Найдено $_coversFound. Нажмите, чтобы остановить'
                        : 'Для треков без обложки: поиск в интернете по '
                            'исполнителю и названию',
                    onTap: _findAllCovers,
                    busy: _coversRunning,
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 4,
                  child: _ActionCard(
                    icon: Icons.manage_search_rounded,
                    title: job.running
                        ? 'Ищу тексты: ${job.done} из ${job.total}'
                        : 'Найти тексты онлайн',
                    subtitle: job.running
                        ? 'Найдено ${job.found}. Нажмите, чтобы остановить'
                        : missing == 0
                            ? 'У всех треков уже есть текст'
                            : 'Без текста: $missing — 5 источников, '
                                'enhanced LRC в приоритете',
                    onTap: job.running
                        ? jobCtl.cancel
                        : (missing == 0 ? null : jobCtl.runMissing),
                    busy: job.running,
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 5,
                  child: _ActionCard(
                    icon: Icons.swap_vert_rounded,
                    title: 'Резервная копия',
                    subtitle: 'JSON с треками, плейлистами и текстами',
                    onTap: _busy ? null : _openBackup,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Недавно добавленные',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${tracks.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final track = shown[i];
            return TrackTile(
              title: track.title,
              artist: track.artist,
              coverPath: track.artworkPath,
              index: i,
              onTap: () => ref
                  .read(audioHandlerProvider)
                  .playTrack(track, contextQueue: shown),
              onMenu: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrackEditSheet(trackId: track.id),
                ),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 44)),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                size: 21,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
