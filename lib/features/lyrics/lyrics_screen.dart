import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(libraryProvider).lyricsFor(widget.trackId);
    final lyrics = raw == null ? const Lyrics() : LrcParser.parse(raw);
    final track = ref.watch(currentTrackProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Текст песни', style: TextStyle(fontSize: 16)),
            if (track != null)
              Text(
                track.artist,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          if (lyrics.synced)
            PopupMenuButton<int>(
              color: AppColors.surfaceAlt,
              icon: const Icon(Icons.sync_alt, size: 20),
              tooltip: 'Сдвиг синхронизации',
              onSelected: (value) => setState(() => _offsetMs = value),
              itemBuilder: (_) => [
                for (final shift in const [-2000, -1000, -500, 0, 500, 1000, 2000])
                  PopupMenuItem(
                    value: shift,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            shift == 0
                                ? 'Без сдвига'
                                : '${shift > 0 ? '+' : ''}${shift / 1000} с',
                          ),
                        ),
                        if (shift == _offsetMs)
                          const Icon(Icons.check, size: 16, color: AppColors.accent),
                      ],
                    ),
                  ),
              ],
            ),
          if (lyrics.isEmpty)
            TextButton(
              onPressed: () async {
                if (track == null) return;
                final result = await ref.read(importProvider).findLyricsOnline(track);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.found ? 'Текст найден' : 'Текст не найден')),
                );
                setState(() {});
              },
              child: const Text('Найти'),
            ),
        ],
      ),
      body: lyrics.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Текст не найден.\nНажмите «Найти» — поиск в LRCLIB по названию и исполнителю.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
              ),
            )
          : lyrics.synced
              ? StreamBuilder<Duration>(
                  stream: ref.watch(audioHandlerProvider).positionStream,
                  builder: (context, snapshot) {
                    final raw = snapshot.data ?? Duration.zero;
                    final position = raw +
                        Duration(milliseconds: _offsetMs);
                    final index = lyrics.indexAt(
                      position < Duration.zero ? Duration.zero : position,
                    );
                    if (index != _activeIndex) {
                      _activeIndex = index;
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _ensureVisible(index),
                      );
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 220),
                      itemCount: lyrics.lines.length,
                      itemBuilder: (context, i) {
                        final active = i == _activeIndex;
                        return GestureDetector(
                          key: _keys.putIfAbsent(i, () => GlobalKey()),
                          onTap: () => ref
                              .read(audioHandlerProvider)
                              .seek(lyrics.lines[i].time),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              lyrics.lines[i].text.isEmpty ? '♪' : lyrics.lines[i].text,
                              style: TextStyle(
                                fontSize: active ? 22 : 18,
                                height: 1.35,
                                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                                color: active
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                  children: [
                    Text(
                      lyrics.plainText,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
    );
  }

  void _ensureVisible(int index) {
    final key = _keys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }
}
