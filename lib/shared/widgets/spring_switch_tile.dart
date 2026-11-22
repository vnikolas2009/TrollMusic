import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'spring_switch.dart';

class SpringSwitchTile extends StatelessWidget {
  const SpringSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 3,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
      trailing: SpringSwitch(
        value: value,
        onChanged: onChanged,
        semanticLabel: title,
      ),
      onTap: () => onChanged(!value),
    );
  }
}
