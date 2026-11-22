import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.avatarUrl,
    this.action,
    this.subtitle,
  });

  final String title;
  final String? avatarUrl;
  final Widget? action;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final avatar = avatarUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 12, 12),
      child: Row(
        children: [
          if (avatar != null && avatar.isNotEmpty) ...[
            ClipOval(
              child: SizedBox(
                width: 28,
                height: 28,
                child: Image.network(
                  avatar,
                  fit: BoxFit.cover,
                  cacheWidth: AppConfig.thumbCacheWidth,
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.surfaceHigh),
                    child: Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Theme(
                // Действия в шапках секций — приглушённые, не конкурируют с заголовком.
                data: Theme.of(context).copyWith(
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                child: action!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Заголовок-«плашка» для пустых экранов и приветствий.
class TrollGreeting extends StatelessWidget {
  const TrollGreeting({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: 1,
              duration: AppMotion.base,
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
