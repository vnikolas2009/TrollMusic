import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';

abstract final class AppTheme {
  /// Тема по умолчанию (для тестов и до инициализации настроек).
  static ThemeData get dark => build(AppPalette.current);

  /// [fontFamily] — семейство выбранного пользователем шрифта; `null` —
  /// стандартный шрифт платформы.
  static ThemeData build(AppPalette p, {String? fontFamily}) {
    final scheme = (p.isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceHigh,
      outline: p.divider,
      outlineVariant: p.surfaceHigh,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
        },
      ),
    );

    final text = base.textTheme
        .apply(
          bodyColor: p.textPrimary,
          displayColor: p.textPrimary,
        )
        .copyWith(
          displayLarge: _title(p, 44, FontWeight.w800, -1.4),
          headlineLarge: _title(p, 30, FontWeight.w800, -0.8),
          headlineMedium: _title(p, 24, FontWeight.w800, -0.6),
          headlineSmall: _title(p, 20, FontWeight.w700, -0.4),
          titleLarge: _title(p, 17, FontWeight.w700, -0.2),
          titleMedium: _title(p, 15, FontWeight.w600, -0.1),
          bodyLarge: _title(p, 15, FontWeight.w500, 0),
          bodyMedium: _title(p, 13, FontWeight.w400, 0),
          labelLarge: _title(p, 13, FontWeight.w600, 0.1),
          labelSmall: _label(p, 10, FontWeight.w700, 1.2),
        )
        .apply(fontFamily: fontFamily);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: p.textPrimary, size: 22),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surfaceAlt,
        showDragHandle: true,
        dragHandleColor: p.textTertiary,
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: p.textPrimary,
        inactiveTrackColor: p.surfaceHigh,
        thumbColor: p.textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceHigh,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceHigh,
        circularTrackColor: p.surfaceHigh,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textPrimary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.textPrimary,
          foregroundColor: p.inverse,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.surfaceHigh),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: p.textPrimary,
        disabledColor: p.surface,
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.inverse,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surfaceAlt,
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          color: p.textTertiary,
          fontSize: 14,
        ),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.textTertiary),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textSecondary,
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: p.textPrimary, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 2),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(3),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.all(p.surfaceHigh),
        crossAxisMargin: 2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.onAccent
              : p.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.accent
              : p.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }

  static TextStyle _title(AppPalette p, double size, FontWeight weight, double spacing) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.2,
        color: p.textPrimary,
      );

  static TextStyle _label(AppPalette p, double size, FontWeight weight, double spacing) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: p.textSecondary,
      );
}
