import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

/// Обложка с мягким появлением и плейсхолдером, который не «прыгает».
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url,
    this.path,
    this.size = 48,
    this.radius = 4,
    this.circle = false,
    this.placeholderColor,
    this.placeholderIcon = Icons.music_note_rounded,
    this.fit = BoxFit.cover,
    this.animate = true,
  });

  final String? url;
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
        circle ? BorderRadius.circular(size / 2) : BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: radiusValue,
      child: SizedBox(
        width: size,
        height: size,
        child: _content(placeholderColor ?? AppColors.surfaceHigh),
      ),
    );
  }

  Widget _content(Color fallback) {
    if (path != null && path!.isNotEmpty) {
      final file = File(path!);
      if (file.existsSync()) {
        return _image(
          Image.file(
            file,
            fit: fit,
            errorBuilder: (_, __, ___) => _placeholder(fallback),
          ),
        );
      }
    }
    if (url != null && url!.isNotEmpty) {
      return _image(
        Image.network(
          url!,
          fit: fit,
          errorBuilder: (_, __, ___) => _placeholder(fallback),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(fallback),
        ),
      );
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
