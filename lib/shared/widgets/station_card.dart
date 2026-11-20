import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'circle_collage.dart';

class StationCard extends StatelessWidget {
  const StationCard({
    super.key,
    required this.title,
    required this.background,
    this.centerUrl,
    this.leftUrl,
    this.rightUrl,
    this.size = 160,
    this.onTap,
  });

  final String title;
  final Color background;
  final String? centerUrl;
  final String? leftUrl;
  final String? rightUrl;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onColor = _onColor(background);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: background,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'YS',
                      style: TextStyle(
                        color: onColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'РАДИО',
                      style: TextStyle(
                        color: onColor.withValues(alpha: 0.75),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: CircleCollage(
                      centerUrl: centerUrl,
                      leftUrl: leftUrl,
                      rightUrl: rightUrl,
                      size: size * 0.58,
                      background: background,
                    ),
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _onColor(Color background) =>
      background.computeLuminance() > 0.55 ? Colors.black : AppColors.textPrimary;
}
