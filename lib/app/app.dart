import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../shared/widgets/splash_gate.dart';
import 'font_controller.dart';
import 'providers.dart';
import 'theme_controller.dart';

class TrollMusicApp extends ConsumerStatefulWidget {
  const TrollMusicApp({super.key});

  @override
  ConsumerState<TrollMusicApp> createState() => _TrollMusicAppState();
}

class _TrollMusicAppState extends ConsumerState<TrollMusicApp>
    with WidgetsBindingObserver {
  int _applied = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (ref.read(themeControllerProvider).mode == ThemeMode.system) {
      setState(() {});
    }
  }

  AppPalette _palette(ThemeState s, Brightness system) {
    final brightness = switch (s.mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => system,
    };

    return AppPalette.build(
      brightness: brightness,
      accent: s.accent,
      amoled: s.amoled,
      gradient: s.gradient,
    );
  }

  /// Цвета читаются через статические геттеры, поэтому при смене палитры
  /// принудительно пересобираем всё дерево (один раз после кадра).
  void _rebuildAll() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(themeControllerProvider);
    final system = MediaQuery.maybePlatformBrightnessOf(context) ??
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    final palette = _palette(state, system);

    final changed = palette.signature != _applied;
    AppPalette.current = palette;

    if (changed) {
      final first = _applied == 0;
      _applied = palette.signature;

      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rebuildAll();
        });
      }
    }

    final theme = AppTheme.build(
      palette,
      fontFamily: ref.watch(fontControllerProvider).family,
    );

    return MaterialApp(
      title: 'TrollMusic',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: palette.isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return child ?? const SizedBox.shrink();
      },
      home: const SplashGate(),
    );
  }
}
