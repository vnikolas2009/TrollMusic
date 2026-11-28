import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lyrics_background_provider.dart';
import '../../core/utils/lyrics_bg.dart';
import 'aurora_background.dart';

/// Фон экрана текстов: выбранная картинка (или GIF) под затемнением либо
/// обычный фон в цвет обложки, если картинки нет или она не читается.
class LyricsBackdrop extends ConsumerWidget {
  const LyricsBackdrop({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(lyricsBackgroundProvider);
    final aurora = AuroraBackground(color: color);
    final path = bg.path;
    if (path == null) return aurora;

    final scrim = lyricsBgScrim(bg.dim, gradient: bg.gradient);

    return Stack(
      fit: StackFit.expand,
      children: [
        aurora,
        // Стандартный layoutBuilder у AnimatedSwitcher ослабляет ограничения
        // (StackFit.loose), и картинка оставалась своего размера, не
        // заполняя экран. Здесь фон растягивается на весь экран с обрезкой
        // по краям (cover).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          child: SizedBox.expand(
            key: ValueKey(path),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: scrim.top),
                Colors.black.withValues(alpha: scrim.bottom),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
