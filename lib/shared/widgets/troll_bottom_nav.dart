import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

/// Плавающая нижняя навигация: стеклянная капсула с «magic pill»,
/// которая скользит между вкладками.
class TrollBottomNav extends StatelessWidget {
  const TrollBottomNav({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_rounded, Icons.home_outlined, 'Главная'),
    (Icons.search_rounded, Icons.search, 'Поиск'),
    (Icons.library_music_rounded, Icons.library_music_outlined, 'Медиатека'),
    (Icons.add_box_rounded, Icons.add_box_outlined, 'Создать'),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final bottomInset = media?.padding.bottom ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomInset),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.cardStrong,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.outline),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / _items.length;
            return Stack(
              children: [
                // Скользящая подсветка активной вкладки.
                AnimatedPositioned(
                  duration: AppMotion.base,
                  curve: AppMotion.emphasized,
                  left: slot * index + 8,
                  top: 8,
                  bottom: 8,
                  width: slot - 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.highlight,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.textPrimary.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: _items[i].$1,
                          iconOutlined: _items[i].$2,
                          label: _items[i].$3,
                          active: index == i,
                          onTap: () => onChanged(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconOutlined,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData iconOutlined;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.textPrimary : AppColors.textTertiary;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: active ? 1 : 0),
              duration: AppMotion.fast,
              curve: AppMotion.press,
              builder: (context, t, child) => Transform.scale(
                scale: 1 + 0.08 * t,
                child: Icon(
                  active ? icon : iconOutlined,
                  size: 23,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              curve: AppMotion.emphasized,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
                color: color,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
