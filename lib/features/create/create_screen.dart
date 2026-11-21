import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/permission_service.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/track_tile.dart';
import 'backup_screen.dart';
import 'track_edit_sheet.dart';
import '../settings/settings_screen.dart';

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  bool _busy = false;

  Future<void> _import() async {
    await PermissionService.requestAudioFiles();
    setState(() => _busy = true);
    try {
      final imported = await ref.read(importProvider).pickAndImportAudio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imported.isEmpty
              ? 'Файлы не выбраны'
              : 'Импортировано треков: ${imported.length}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка импорта: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localTracksProvider).value ?? const <Track>[];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background.withValues(alpha: 0.92),
          surfaceTintColor: Colors.transparent,
          title: const Text('Создать'),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(
                  index: 0,
                  child: _ActionCard(
                    icon: Icons.upload_file_rounded,
                    title: 'Импортировать аудио',
                    subtitle: 'MP3, M4A, FLAC, WAV с памяти устройства',
                    onTap: _busy ? null : _import,
                    busy: _busy,
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 1,
                  child: _ActionCard(
                    icon: Icons.cloud_download_outlined,
                    title: 'Импорт плейлиста Spotify',
                    subtitle: 'Вставьте ссылку — треки появятся в медиатеке',
                    onTap: () => _importSpotify(context),
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 2,
                  child: _ActionCard(
                    icon: Icons.swap_vert_rounded,
                    title: 'Экспорт / импорт медиатеки',
                    subtitle: 'JSON-резервная копия всей библиотеки',
                    onTap: () => _openBackup(context),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Локальные треки',
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
                        '${local.length}',
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
          itemCount: local.length,
          itemBuilder: (context, i) {
            final track = local[i];
            return TrackTile(
              title: track.title,
              artist: track.artist,
              coverUrl: track.thumbnailUrl,
              coverPath: track.artworkPath,
              downloaded:
                  track.localPath != null && track.localPath!.isNotEmpty,
              index: i,
              onTap: () => ref
                  .read(audioHandlerProvider)
                  .playTrack(track, contextQueue: local),
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

  Future<void> _importSpotify(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Ссылка Spotify'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://open.spotify.com/playlist/...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text;
              Navigator.pop(dialogContext);
              await _performSpotifyImport(url);
            },
            child: const Text('Импорт'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _performSpotifyImport(String url) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(musicRepositoryProvider);
      final playlist = await repo.spotifyPlaylist(url);
      if (playlist == null) throw StateError('Неверная ссылка');
      await ref.read(libraryProvider).savePlaylist(playlist);
      await ref.read(libraryProvider).saveTracks(playlist.tracks);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортировано: ${playlist.tracks.length} треков')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось импортировать: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openBackup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackupScreen()),
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
      onTap: busy ? null : onTap,
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
              child: Icon(icon, size: 21, color: AppColors.accent),
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
                child: CircularProgressIndicator(strokeWidth: 2),
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
