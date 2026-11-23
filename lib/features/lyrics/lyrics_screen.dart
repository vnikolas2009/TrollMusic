import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/network/lyrics/external_lyrics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/read_along_text.dart';
import 'aurora_background.dart';

const _defaultAurora = Color(0xFF3A4570);

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final _scrollController = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _activeIndex = -1;
  int _offsetMs = 0;
  Color _aurora = _defaultAurora;
  String? _colorSourceId;

  @override
  void initState() {
    super.initState();
    _offsetMs = ref.read(settingsProvider).lyricsOffsetMs(widget.trackId);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveColor(Track track) async {
    if (_colorSourceId == track.id) return;
    _colorSourceId = track.id;

    ImageProvider? image;
    final local = track.artworkPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      image = FileImage(File(local));
    } else if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty) {
      image = NetworkImage(track.thumbnailUrl!);
    }
    if (image == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        image,
        size: const Size(96, 96),
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color;
      if (color != null && mounted) setState(() => _aurora = color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(libraryProvider).lyricsFor(widget.trackId);
    final lyrics = raw == null ? const Lyrics() : LrcParser.parse(raw);
    final track = ref.watch(currentTrackProvider).value;
    if (track != null) _resolveColor(track);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track?.title ?? 'Текст песни',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (track != null)
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (lyrics.synced) _offsetMenu(),
          _lyricsMenu(context, track, raw),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AuroraBackground(color: _aurora)),
          Positioned.fill(child: _body(lyrics)),
        ],
      ),
    );
  }

  Widget _offsetMenu() {
    return PopupMenuButton<int>(
      color: AppColors.surfaceAlt,
      icon: const Icon(Icons.sync_alt, size: 20),
      tooltip: 'Сдвиг синхронизации',
      onSelected: (value) {
        setState(() => _offsetMs = value);
        ref.read(settingsProvider).setLyricsOffsetMs(widget.trackId, value);
      },
      itemBuilder: (_) => [
        for (final shift in const [-2000, -1000, -500, 0, 500, 1000, 2000])
          PopupMenuItem(
            value: shift,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shift == 0 ? 'Без сдвига' : '${shift > 0 ? '+' : ''}${shift / 1000} с',
                  ),
                ),
                if (shift == _offsetMs)
                  Icon(Icons.check, size: 16, color: AppColors.accent),
              ],
            ),
          ),
      ],
    );
  }

  Widget _lyricsMenu(BuildContext context, Track? track, String? raw) {
    // `null` — автопоиск по всем источникам, `_custom` — свой текст.
    const custom = -1;
    const auto = -2;
    return PopupMenuButton<int>(
      color: AppColors.surfaceAlt,
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Текст песни',
      onSelected: (value) async {
        if (track == null) return;
        if (value == custom) {
          await _editOwn(context, raw);
          return;
        }
        final source = value == auto ? null : LyricsSource.values[value];
        final result = await ref
            .read(importProvider)
            .findLyricsOnline(track, source: source);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.found
                  ? 'Текст найден${result.source == null ? '' : ' · ${result.source!.label}'}'
                  : 'Текст не найден',
            ),
          ),
        );
        setState(() {});
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: auto,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.search_rounded),
            title: Text('Найти автоматически'),
          ),
        ),
        for (final source in LyricsSource.values)
          PopupMenuItem(
            value: source.index,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.library_books_outlined),
              title: Text(source.label),
              subtitle: Text(source.hint),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: custom,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_note_rounded),
            title: Text('Свой текст'),
            subtitle: Text('Вставьте текст или LRC с таймкодами'),
          ),
        ),
      ],
    );
  }

  /// Ввод своего текста. Если в нём есть таймкоды `[мм:сс.хх]`, строки
  /// будут подсвечиваться синхронно.
  Future<void> _editOwn(BuildContext context, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Свой текст',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Обычный текст или LRC: [00:12.50] строка',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 8,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Вставьте текст песни…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, controller.text),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    final text = saved?.trim();
    if (text == null || text.isEmpty) return;
    await ref.read(importProvider).saveManualLyrics(widget.trackId, text);
    if (mounted) setState(() {});
  }

  Widget _body(Lyrics lyrics) {
    if (lyrics.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Текст не найден.\nОткройте меню ⋮ вверху: поиск в LRCLIB, Lyrics.ovh, Genius или «Свой текст».',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
        ),
      );
    }
    if (!lyrics.synced) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 110, 24, 120),
        children: [
          Text(
            lyrics.plainText,
            style: const TextStyle(fontSize: 20, height: 1.6, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    final positions = ref.watch(audioHandlerProvider).positionStream;
    Duration shifted(Duration raw) {
      final value = raw + Duration(milliseconds: _offsetMs);
      return value < Duration.zero ? Duration.zero : value;
    }

    // Список перестраивается только при смене активной строки, а не на
    // каждый тик позиции. Тики слушает лишь прогресс активной строки.
    final indexes = positions.map((p) => lyrics.indexAt(shifted(p))).distinct();

    return StreamBuilder<int>(
      stream: indexes,
      initialData: -1,
      builder: (context, snapshot) {
        final index = snapshot.data ?? -1;
        if (index != _activeIndex) {
          _activeIndex = index;
          WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(index));
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 120, 24, 260),
          itemCount: lyrics.lines.length,
          itemBuilder: (context, i) {
            final line = lyrics.lines[i];
            final distance = index < 0 ? 99 : i - index;
            Widget child;
            if (i == index) {
              final end = i + 1 < lyrics.lines.length
                  ? lyrics.lines[i + 1].time
                  : line.time + const Duration(seconds: 5);
              final span = (end - line.time).inMilliseconds;
              child = StreamBuilder<Duration>(
                stream: positions,
                builder: (context, position) {
                  final safe = shifted(position.data ?? Duration.zero);
                  final progress = span > 0
                      ? ((safe - line.time).inMilliseconds / span).clamp(0.0, 1.0).toDouble()
                      : 0.0;
                  return _LyricLine(text: line.text, distance: 0, progress: progress);
                },
              );
            } else {
              child = _LyricLine(text: line.text, distance: distance, progress: 0);
            }
            return GestureDetector(
              key: _keys.putIfAbsent(i, () => GlobalKey()),
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(audioHandlerProvider).seek(line.time),
              child: RepaintBoundary(child: child),
            );
          },
        );
      },
    );
  }

  void _ensureVisible(int index) {
    final ctx = _keys[index]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.32,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Строка текста: активная заливается слева направо по времени,
/// соседние тем сильнее размыты, чем дальше от активной.
class _LyricLine extends StatelessWidget {
  const _LyricLine({required this.text, required this.distance, required this.progress});

  final String text;
  final int distance;
  final double progress;

  static const _style = TextStyle(
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final label = text.isEmpty ? '♪' : text;
    final active = distance == 0;

    Widget child;
    if (active) {
      // Read along: за читаемым словом едет пилюля на пружинах. У пустой
      // строки («♪») слов для подсветки нет, её рисуем обычным текстом.
      child = text.trim().isEmpty
          ? Text(label, style: _style)
          : ReadAlongText(text: text, progress: progress, style: _style);
    } else {
      // Без blur: удалённые строки просто плавно гаснут, но остаются читаемыми.
      final dist = distance.abs();
      final alpha = (0.62 - dist * 0.05).clamp(0.34, 0.62).toDouble();
      child = Text(
        label,
        style: _style.copyWith(color: Colors.white.withValues(alpha: alpha)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}
