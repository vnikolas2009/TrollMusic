import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class TrollBottomNav extends StatelessWidget {
  const TrollBottomNav({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_filled, Icons.home_outlined, 'Главная'),
    (Icons.search, Icons.search, 'Поиск'),
    (Icons.library_music, Icons.library_music_outlined, 'Медиатека'),
    (Icons.add_box, Icons.add_box_outlined, 'Создать'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        index == i ? _items[i].$1 : _items[i].$2,
                        size: 22,
                        color: index == i ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _items[i].$3,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: index == i ? FontWeight.w600 : FontWeight.w400,
                          color: index == i ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
