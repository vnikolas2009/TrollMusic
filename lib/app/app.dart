import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../shared/widgets/splash_gate.dart';

class TrollMusicApp extends StatelessWidget {
  const TrollMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrollMusic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashGate(),
    );
  }
}
