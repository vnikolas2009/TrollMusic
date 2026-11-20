import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class ExplicitBadge extends StatelessWidget {
  const ExplicitBadge({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.textSecondary,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'E',
        style: TextStyle(
          fontSize: size * 0.66,
          height: 1,
          fontWeight: FontWeight.w700,
          color: AppColors.background,
        ),
      ),
    );
  }
}
