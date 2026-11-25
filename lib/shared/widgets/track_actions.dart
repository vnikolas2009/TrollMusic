import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../features/create/track_edit_sheet.dart';
import 'cover_art.dart';

void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Единое меню действий над треком для всех списков.
///
/// [onRemove] показывает пункт «убрать из списка» (например, из плейлиста);
/// сам трек из медиатеки при этом не удаляется.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  String removeLabel = 'Убрать из списка',
  VoidCallback? onRemove,
}) {
  final audio = ref.read(audioHandlerProvider);
  final library = ref.read(libraryProvider);
  final liked = library.isLiked(track.id);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceAlt,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CoverArt(path: track.artworkPath, size: 44, radius: 8),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.skip_next_rounded),
              title: const Text('Играть следующим'),
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await audio.playNext(track);
                _say(context, ok ? 'Будет играть следующим' : 'Файл трека не найден');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Добавить в очередь'),
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await audio.addToQueue(track);
                _say(context, ok ? 'Добавлено в очередь' : 'Файл трека не найден');
              },
            ),
            ListTile(
              leading: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              title: Text(liked ? 'Убрать из избранного' : 'В избранное'),
              onTap: () async {
                Navigator.pop(sheet);
                await library.toggleLike(track.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Добавить в плейлист'),
              onTap: () {
                Navigator.pop(sheet);
                addTrackToPlaylist(context, ref, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Теги, обложка, текст'),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TrackEditSheet(trackId: track.id)),
                );
              },
            ),
            if (onRemove != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: Text(removeLabel),
                onTap: () {
                  Navigator.pop(sheet);
                  onRemove();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Удалить с устройства'),
              onTap: () {
                Navigator.pop(sheet);
                confirmDeleteTrack(context, ref, track);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> confirmDeleteTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Удалить трек?'),
      content: Text('«${track.title}» будет удалён из медиатеки вместе с файлом, обложкой и текстом.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Удалить')),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(storageProvider).deleteTrack(track.id);
  _say(context, 'Трек удалён');
}

/// Выбор плейлиста для трека, с возможностью создать новый.
Future<void> addTrackToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final library = ref.read(libraryProvider);
  final playlists = library.playlists;

  final choice = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: AppColors.surfaceAlt,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Добавить в плейлист', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Новый плейлист'),
              onTap: () => Navigator.pop(sheet, 'new'),
            ),
            for (final playlist in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${playlist.tracks.length} треков'),
                onTap: () => Navigator.pop(sheet, playlist),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice is Playlist) {
    if (choice.tracks.any((t) => t.id == track.id)) {
      _say(context, 'Трек уже в «${choice.title}»');
      return;
    }
    await library.savePlaylist(choice.copyWith(tracks: [...choice.tracks, track]));
    _say(context, 'Добавлено в «${choice.title}»');
    return;
  }

  final name = await askText(context, title: 'Новый плейлист', hint: 'Название');
  if (name == null || name.isEmpty) return;
  await library.savePlaylist(Playlist(
    id: 'user:${DateTime.now().millisecondsSinceEpoch}',
    title: name,
    tracks: [track],
  ));
  _say(context, 'Плейлист «$name» создан');
}

/// Диалог с одним текстовым полем. Возвращает введённый текст или `null`.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  String confirm = 'Готово',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(dialog, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text.trim()),
          child: Text(confirm),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
