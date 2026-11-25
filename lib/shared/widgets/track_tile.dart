import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'explicit_badge.dart';

/// Строка трека: при нажатии подсвечивается фоном, а не «прыгает».
class TrackTile extends StatefulWidget {
  const TrackTile({
    super.key,
    required this.title,
    required this.artist,
    this.coverPath,
    this.explicit = false,
    this.subtitleExtra,
    this.hasLyrics = false,
    this.onTap,
    this.onMenu,
    this.trailing,
    this.leading,
    this.showCover = true,
    this.active = false,
    this.index,
  });

  final String title;
  final String artist;
  final String? coverPath;
  final bool explicit;
  /// Короткая подпись справа от исполнителя (например, длительность).
  final String? subtitleExtra;

  /// У трека есть текст песни.
  final bool hasLyrics;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final Widget? trailing;
  final Widget? leading;
  final bool showCover;
  final bool active;

  /// Позиция в списке: используется для каскадного появления.
  final int? index;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final highlighted = _pressed || widget.active;

    final row = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.surfaceAlt
            : AppColors.surfaceAlt.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (widget.leading != null)
            widget.leading!
          else if (widget.showCover) ...[
            _Cover(path: widget.coverPath),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.active
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (widget.explicit) ...[
                      const ExplicitBadge(),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        widget.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.subtitleExtra != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                widget.subtitleExtra!,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            ),
          if (widget.hasLyrics)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.lyrics_outlined,
                size: 15,
                color: AppColors.textTertiary,
              ),
            ),
          if (widget.trailing != null)
            widget.trailing!
          else
            IconButton(
              onPressed: widget.onMenu,
              icon: const Icon(Icons.more_horiz),
              color: AppColors.textTertiary,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: row,
    );

    if (index == null) return interactive;
    return _TileEntrance(index: index, child: interactive);
  }
}

/// Появление строки списка с короткой задержкой по индексу.
class _TileEntrance extends StatefulWidget {
  const _TileEntrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TileEntrance> createState() => _TileEntranceState();
}

class _TileEntranceState extends State<_TileEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final delay = widget.index.clamp(0, AppMotion.staggerMaxIndex).toInt() *
        AppMotion.staggerStep.inMilliseconds;
    _timer = Timer(Duration(milliseconds: delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CoverImage(path: path),
      ),
    );
  }
}

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, this.path, this.radius = 4});

  final String? path;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceHigh,
      child: path != null && path!.isNotEmpty
          ? Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: AppConfig.thumbCacheWidth,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Icon(
        Icons.music_note_rounded,
        color: AppColors.textSecondary,
        size: 20,
      );
}
