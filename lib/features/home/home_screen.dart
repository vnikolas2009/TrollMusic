import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background,
          title: Text('YSPlayer'),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.settings_outlined),
            ),
          ],
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'Каркас готов',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
