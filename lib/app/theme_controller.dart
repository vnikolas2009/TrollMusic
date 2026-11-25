import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings.dart';
import 'settings_provider.dart';

/// Готовые акцентные цвета для настройки темы.
const kAccentChoices = <Color>[
  Color(0xFF1ED760),
  Color(0xFF3B82F6),
  Color(0xFFA855F7),
  Color(0xFFEC4899),
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF14B8A6),
  Color(0xFFE5E5E5),
];

@immutable
class ThemeState {
  const ThemeState({
    required this.mode,
    required this.accent,
    required this.amoled,
    required this.gradient,
  });

  final ThemeMode mode;
  final Color accent;
  final bool amoled;
  final bool gradient;

  ThemeState copyWith({
    ThemeMode? mode,
    Color? accent,
    bool? amoled,
    bool? gradient,
  }) =>
      ThemeState(
        mode: mode ?? this.mode,
        accent: accent ?? this.accent,
        amoled: amoled ?? this.amoled,
        gradient: gradient ?? this.gradient,
      );
}

/// Тема: режим (тёмная/светлая/системная), акцент, AMOLED и градиент.
/// Сохраняется в [Settings] и применяется мгновенно.
class ThemeController extends Notifier<ThemeState> {
  Settings get _settings => ref.read(settingsProvider);

  @override
  ThemeState build() {
    final s = _settings;
    final index = s.themeModeIndex.clamp(0, 2);
    return ThemeState(
      // 0 = тёмная, 1 = светлая, 2 = системная
      mode: const [ThemeMode.dark, ThemeMode.light, ThemeMode.system][index],
      accent: Color(s.accentValue),
      amoled: s.amoled,
      gradient: s.gradientBackground,
    );
  }

  void setMode(ThemeMode mode) {
    _settings.themeModeIndex = switch (mode) {
      ThemeMode.dark => 0,
      ThemeMode.light => 1,
      ThemeMode.system => 2,
    };
    state = state.copyWith(mode: mode);
  }

  void setAccent(Color color) {
    _settings.accentValue = color.toARGB32();
    state = state.copyWith(accent: color);
  }

  void setAmoled(bool value) {
    _settings.amoled = value;
    state = state.copyWith(amoled: value);
  }

  void setGradient(bool value) {
    _settings.gradientBackground = value;
    state = state.copyWith(gradient: value);
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeState>(ThemeController.new);
