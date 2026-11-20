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
  int _activeIndex = -1;
  static const _lineHeight = 44.0;

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
                    final position = snapshot.data ?? Duration.zero;
                    final index = lyrics.indexAt(position);
                    if (index != _activeIndex) {
                      _activeIndex = index;
                      _autoScroll(index, lyrics.lines.length);
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 220),
                      itemCount: lyrics.lines.length,
                      itemBuilder: (context, i) {
                        final active = i == _activeIndex;
                        return GestureDetector(
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

  void _autoScroll(int index, int total) {
    if (index < 0 || !_scrollController.hasClients) return;
    final target = (index * _lineHeight - 120).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }
}
