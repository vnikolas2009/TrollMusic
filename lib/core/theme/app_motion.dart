import 'package:flutter/material.dart';

/// Токены движения: единые длительности и кривые для всего приложения.
///
/// Кривые подобраны под «пружинные» микроанимации: быстрый старт и мягкое
/// затухание без овершута, чтобы анимации оставались дешёвыми (только
/// opacity и transform — это GPU-композиция).
abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration slower = Duration(milliseconds: 620);

  /// Основная кривая: easeOutQuint-ish, ощущается как пружина.
  static const Curve emphasized = Cubic(0.16, 1, 0.3, 1);

  /// Вход элементов (списки, карточки).
  static const Curve enter = Cubic(0.22, 1, 0.36, 1);

  /// Выход/закрытие.
  static const Curve exit = Cubic(0.4, 0, 0.2, 1);

  /// Лёгкий «отскок» для нажатий.
  static const Curve press = Cubic(0.34, 1.56, 0.64, 1);

  /// Шаг stagger-задержки между элементами списка.
  static const Duration staggerStep = Duration(milliseconds: 36);

  static const int staggerMaxIndex = 8;
}

/// Переход между экранами: fade + короткий подъём снизу.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;

    final enter = CurvedAnimation(
      parent: animation,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.exit,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.72, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      ),
    );
  }
}
