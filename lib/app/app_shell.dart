import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../features/home/home_screen.dart';
import '../shared/widgets/mini_player.dart';
import '../shared/widgets/ys_bottom_nav.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(bottom: false, child: HomeScreen(key: ValueKey(_index))),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          YsBottomNav(
            index: _index,
            onChanged: (i) => setState(() => _index = i),
          ),
        ],
      ),
    );
  }
}
