import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'press_scale.dart';

/// Кнопка-«таблетка» с плавным переключением выбранного состояния.
///
/// Выбранный элемент получает светлый фон, остальные — приглушённый текст.
class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            _PillItem(
              label: labels[i],
              selected: i == index,
              padding: padding,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.label,
    required this.selected,
    required this.padding,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.black : AppColors.textSecondary,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
