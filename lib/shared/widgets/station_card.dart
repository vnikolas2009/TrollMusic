import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'circle_collage.dart';
import 'press_scale.dart';

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
    return PressScale(
      onTap: onTap,
      scale: 0.965,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: background.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        background,
                        Color.lerp(background, Colors.black, 0.28)!,
                      ],
                    ),
                  ),
                ),
                // Мягкий блик сверху — «стеклянность» без blur.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TROLL',
                            style: TextStyle(
                              color: onColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'РАДИО',
                            style: TextStyle(
                              color: onColor.withValues(alpha: 0.7),
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
