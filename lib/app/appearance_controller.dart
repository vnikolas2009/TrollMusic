import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/appearance.dart';
import 'settings_provider.dart';

@immutable
class AppearanceState {
  const AppearanceState({
    this.weightLevel = 1,
    this.textScale = 1.0,
    this.animation = AnimationMode.smooth,
    this.effects = EffectsLevel.normal,
    this.coverShape = CoverShape.rounded,
    this.lyricsScale = 1.0,
    this.showLyricPreview = true,
  });

  /// Толщина шрифта: 0 — тонкий … 3 — жирный (у встроенных шрифтов).
  final int weightLevel;

  /// Масштаб текста интерфейса (поверх системного).
  final double textScale;

  final AnimationMode animation;
  final EffectsLevel effects;
  final CoverShape coverShape;

  /// Масштаб текста песен.
  final double lyricsScale;

  /// Строка текста под обложкой в плеере.
  final bool showLyricPreview;

  AppearanceState copyWith({
    int? weightLevel,
    double? textScale,
    AnimationMode? animation,
    EffectsLevel? effects,
    CoverShape? coverShape,
    double? lyricsScale,
    bool? showLyricPreview,
  }) =>
      AppearanceState(
        weightLevel: weightLevel ?? this.weightLevel,
        textScale: textScale ?? this.textScale,
        animation: animation ?? this.animation,
        effects: effects ?? this.effects,
        coverShape: coverShape ?? this.coverShape,
        lyricsScale: lyricsScale ?? this.lyricsScale,
        showLyricPreview: showLyricPreview ?? this.showLyricPreview,
      );

  @override
  bool operator ==(Object other) =>
      other is AppearanceState &&
      other.weightLevel == weightLevel &&
      other.textScale == textScale &&
      other.animation == animation &&
      other.effects == effects &&
      other.coverShape == coverShape &&
      other.lyricsScale == lyricsScale &&
      other.showLyricPreview == showLyricPreview;

  @override
  int get hashCode => Object.hash(
        weightLevel,
        textScale,
        animation,
        effects,
        coverShape,
        lyricsScale,
        showLyricPreview,
      );
}

/// Косметические настройки: сохраняются в настройках и применяются сразу.
class AppearanceController extends Notifier<AppearanceState> {
  @override
  AppearanceState build() {
    final s = ref.read(settingsProvider);
    final state = AppearanceState(
      weightLevel: s.weightLevel,
      textScale: s.textScale,
      animation: AnimationMode.byIndex(s.animationModeIndex),
      effects: EffectsLevel.byIndex(s.effectsIndex),
      coverShape: CoverShape.byIndex(s.coverShapeIndex),
      lyricsScale: s.lyricsScale,
      showLyricPreview: s.showLyricPreview,
    );
    _apply(state);
    return state;
  }

  /// Выставляет глобальные значения, которые читаются вне провайдеров:
  /// скорость анимаций и параметры [AppAppearance].
  void _apply(AppearanceState s) {
    timeDilation = s.animation.timeDilation;
    AppAppearance.effects = s.effects;
    AppAppearance.coverShape = s.coverShape;
  }

  void _update(AppearanceState next) {
    _apply(next);
    state = next;
  }

  void setWeightLevel(int level) {
    final value = level.clamp(0, 3);
    ref.read(settingsProvider).weightLevel = value;
    _update(state.copyWith(weightLevel: value));
  }

  void setTextScale(double scale) {
    final value = scale
        .clamp(TextScaleRange.interfaceMin, TextScaleRange.interfaceMax)
        .toDouble();
    ref.read(settingsProvider).textScale = value;
    _update(state.copyWith(textScale: value));
  }

  void setLyricsScale(double scale) {
    final value = scale
        .clamp(TextScaleRange.lyricsMin, TextScaleRange.lyricsMax)
        .toDouble();
    ref.read(settingsProvider).lyricsScale = value;
    _update(state.copyWith(lyricsScale: value));
  }

  void setAnimation(AnimationMode mode) {
    ref.read(settingsProvider).animationModeIndex = mode.index;
    _update(state.copyWith(animation: mode));
  }

  void setEffects(EffectsLevel level) {
    ref.read(settingsProvider).effectsIndex = level.index;
    _update(state.copyWith(effects: level));
  }

  void setCoverShape(CoverShape shape) {
    ref.read(settingsProvider).coverShapeIndex = shape.index;
    _update(state.copyWith(coverShape: shape));
  }

  void setShowLyricPreview(bool value) {
    ref.read(settingsProvider).showLyricPreview = value;
    _update(state.copyWith(showLyricPreview: value));
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceState>(
  AppearanceController.new,
);
