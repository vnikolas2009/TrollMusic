import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.divider,
      outlineVariant: AppColors.surfaceHigh,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
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
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          displayLarge: _title(44, FontWeight.w800, -1.4),
          headlineLarge: _title(30, FontWeight.w800, -0.8),
          headlineMedium: _title(24, FontWeight.w800, -0.6),
          headlineSmall: _title(20, FontWeight.w700, -0.4),
          titleLarge: _title(17, FontWeight.w700, -0.2),
          titleMedium: _title(15, FontWeight.w600, -0.1),
          bodyLarge: _title(15, FontWeight.w500, 0),
          bodyMedium: _title(13, FontWeight.w400, 0),
          labelLarge: _title(13, FontWeight.w600, 0.1),
          labelSmall: _label(10, FontWeight.w700, 1.2),
        );

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surfaceAlt,
        showDragHandle: true,
        dragHandleColor: AppColors.textTertiary,
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: AppColors.textPrimary,
        inactiveTrackColor: AppColors.surfaceHigh,
        thumbColor: AppColors.textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: Colors.black,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.surfaceHigh),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.textPrimary,
        disabledColor: AppColors.surface,
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 14,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
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
          borderSide: const BorderSide(color: AppColors.textTertiary),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.textPrimary, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 2),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(3),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.all(AppColors.surfaceHigh),
        crossAxisMargin: 2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }

  static TextStyle _title(double size, FontWeight weight, double spacing) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.2,
        color: AppColors.textPrimary,
      );

  static TextStyle _label(double size, FontWeight weight, double spacing) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: AppColors.textSecondary,
      );
}
