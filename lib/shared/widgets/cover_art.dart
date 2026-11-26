import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/app_motion.dart';

/// Обложка с мягким появлением и плейсхолдером, который не «прыгает».
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.path,
    this.size = 48,
    this.radius = 4,
    this.circle = false,
    this.placeholderColor,
    this.placeholderIcon = Icons.music_note_rounded,
    this.fit = BoxFit.cover,
    this.animate = true,
  });

  final String? path;
  final double size;
  final double radius;
  final bool circle;
  final Color? placeholderColor;
  final IconData placeholderIcon;
  final BoxFit fit;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final radiusValue =
        circle
            ? BorderRadius.circular(size / 2)
            : BorderRadius.circular(AppAppearance.coverRadius(radius));
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size * devicePixelRatio).round().clamp(32, 1200);
    return ClipRRect(
      borderRadius: radiusValue,
      child: SizedBox(
        width: size,
        height: size,
        child: _content(placeholderColor ?? AppColors.surfaceHigh, cacheWidth),
      ),
    );
  }

  Widget _content(Color fallback, int cacheWidth) {
    if (path != null && path!.isNotEmpty) {
      final file = File(path!);
      if (file.existsSync()) {
        return _image(
          Image.file(
            file,
            fit: fit,
            cacheWidth: cacheWidth,
            errorBuilder: (_, __, ___) => _placeholder(fallback),
          ),
        );
      }
    }
    return _placeholder(fallback);
  }

  Widget _image(Widget child) {
    if (!animate) return child;
    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.enter,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }

  Widget _placeholder(Color fallback) => Container(
        color: fallback,
        alignment: Alignment.center,
        child: Icon(
          placeholderIcon,
          color: AppColors.textSecondary,
          size: size * 0.34,
        ),
      );
}


/// Мозаика 2×2 из обложек треков; если обложек меньше четырёх —
/// одна крупная обложка первого трека.
class CoverMosaic extends StatelessWidget {
  const CoverMosaic({
    super.key,
    required this.paths,
    this.size = 56,
    this.radius = 12,
    this.icon = Icons.music_note_rounded,
  });

  final List<String?> paths;
  final double size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final real = paths.whereType<String>().where((p) => p.isNotEmpty).toList();
    if (real.length < 4) {
      return CoverArt(
        path: real.isEmpty ? null : real.first,
        size: size,
        radius: radius,
        placeholderIcon: icon,
        animate: false,
      );
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppAppearance.coverRadius(radius)),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [
            for (final path in real.take(4))
              CoverArt(path: path, size: half, radius: 0, animate: false),
          ],
        ),
      ),
    );
  }
}
