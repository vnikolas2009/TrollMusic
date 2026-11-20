import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'cover_art.dart';

class CircleCollage extends StatelessWidget {
  const CircleCollage({
    super.key,
    this.centerUrl,
    this.centerPath,
    this.leftUrl,
    this.rightUrl,
    this.size = 120,
    this.background = Colors.transparent,
  });

  final String? centerUrl;
  final String? centerPath;
  final String? leftUrl;
  final String? rightUrl;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final main = size * 0.62;
    final side = size * 0.38;
    final border = background == Colors.transparent ? Colors.black12 : background;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: _Bubble(
              url: leftUrl,
              size: side,
              border: border,
              opacity: 0.92,
            ),
          ),
          Positioned(
            right: 0,
            child: _Bubble(
              url: rightUrl,
              size: side,
              border: border,
              opacity: 0.92,
            ),
          ),
          _Bubble(
            url: centerUrl,
            path: centerPath,
            size: main,
            border: border,
            elevated: true,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    this.url,
    this.path,
    required this.size,
    required this.border,
    this.opacity = 1,
    this.elevated = false,
  });

  final String? url;
  final String? path;
  final double size;
  final Color border;
  final double opacity;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: border, width: elevated ? 3 : 2),
          boxShadow: elevated
              ? const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))]
              : null,
        ),
        child: CoverArt(
          url: url,
          path: path,
          size: size,
          circle: true,
          placeholderColor: AppColors.surfaceHigh,
        ),
      ),
    );
  }
}
