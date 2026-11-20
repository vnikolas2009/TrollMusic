import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'explicit_badge.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.coverPath,
    this.explicit = false,
    this.downloaded = false,
    this.downloadProgress,
    this.onTap,
    this.onMenu,
    this.trailing,
    this.leading,
    this.showCover = true,
  });

  final String title;
  final String artist;
  final String? coverUrl;
  final String? coverPath;
  final bool explicit;
  final bool downloaded;
  final double? downloadProgress;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final Widget? trailing;
  final Widget? leading;
  final bool showCover;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            if (leading != null)
              leading!
            else if (showCover) ...[
              _Cover(url: coverUrl, path: coverPath),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (explicit) ...[
                        const ExplicitBadge(),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
            if (downloadProgress != null)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: downloadProgress,
                  strokeWidth: 2,
                ),
              )
            else if (downloaded)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.download_done_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
            if (trailing != null)
              trailing!
            else
              IconButton(
                onPressed: onMenu,
                icon: const Icon(Icons.more_horiz),
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url, this.path});

  final String? url;
  final String? path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CoverImage(url: url, path: path),
      ),
    );
  }
}

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, this.url, this.path, this.radius = 4});

  final String? url;
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
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : (url != null && url!.isNotEmpty
              ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
              : _fallback()),
    );
  }

  Widget _fallback() => const Icon(
        Icons.music_note_rounded,
        color: AppColors.textSecondary,
        size: 20,
      );
}
