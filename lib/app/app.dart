import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../shared/widgets/splash_gate.dart';

class YSPlayerApp extends StatelessWidget {
  const YSPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YSPlayer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashGate(),
    );
  }
}
