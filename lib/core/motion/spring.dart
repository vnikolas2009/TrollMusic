import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

/// Пара «жёсткость, демпфирование» — как `stiffness damping` в tokens.css.
typedef SpringSpec = (double stiffness, double damping);

/// Пружина-осциллятор. Те же формулы, что в `motion.js` (DesignBookmark):
/// `a = -k·(x - t) - c·v`, полунеявный Эйлер (сначала скорость, потом позиция).
class Spring {
  Spring(this.x, [this.k = 400, this.c = 30]) : t = x;

  /// Текущее значение, скорость и цель.
  double x;
  double v = 0;
  double t;

  /// Жёсткость и демпфирование.
  double k;
  double c;

  /// Меняет параметры. При `reduceMotion` демпфирование критическое
  /// (`2·√k`): пружина приходит к цели без колебаний и перелёта.
  void tune(SpringSpec spec, {bool reduceMotion = false}) {
    k = spec.$1;
    c = reduceMotion ? criticalDamping(spec.$1) : spec.$2;
  }

  void step(double dt) {
    final a = -k * (x - t) - c * v;
    v += a * dt;
    x += v * dt;
  }

  /// Пружина практически остановилась на цели.
  bool get atRest => (x - t).abs() < 0.0005 && v.abs() < 0.005;
}

double criticalDamping(double stiffness) => 2 * math.sqrt(stiffness);

/// Шаг по времени одного кадра: не больше 1/30 с, чтобы после паузы
/// (свёрнутое приложение) пружины не «взрывались».
double frameDelta(Duration elapsed, Duration previous) {
  final seconds = (elapsed - previous).inMicroseconds / 1000000.0;
  return seconds.clamp(0.0, 1 / 30).toDouble();
}

/// Двигает все пружины на [dt] за [substeps] подшагов (как в движке сайта:
/// жёсткие пружины устойчивее при мелком шаге).
void stepSprings(Iterable<Spring> springs, double dt, {int substeps = 4}) {
  final sub = dt / substeps;
  for (var i = 0; i < substeps; i++) {
    for (final spring in springs) {
      spring.step(sub);
    }
  }
}

/// Цикл кадров для анимаций на пружинах: вызывает [onFrame] с `dt` в секундах.
///
/// Владеет `Ticker`; создаётся из `State` с `SingleTickerProviderStateMixin`
/// и обязательно закрывается в `dispose`.
class SpringLoop {
  SpringLoop(TickerProvider vsync, this.onFrame) {
    _ticker = vsync.createTicker(_tick);
  }

  final void Function(double dt) onFrame;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = frameDelta(elapsed, _last);
    _last = elapsed;
    onFrame(dt);
  }

  void dispose() => _ticker.dispose();
}

/// Пружины из tokens.css DesignBookmark (значения скопированы без изменений).
abstract final class SpringTokens {
  // Read Along (константы из его скрипта)
  static const SpringSpec readLead = (520.0, 40.0);
  static const SpringSpec readTrail = (210.0, 26.0);
  static const SpringSpec readLine = (600.0, 48.0);
  static const SpringSpec readFade = (300.0, 30.0);

  // Rubber Dock
  static const SpringSpec dockLead = (640.0, 38.0);
  static const SpringSpec dockTrail = (150.0, 16.0);
  static const SpringSpec dockDragLead = (1100.0, 56.0);
  static const SpringSpec dockDragTrail = (320.0, 26.0);
  static const SpringSpec dockOpenW = (340.0, 21.0);
  static const SpringSpec dockOpenH = (230.0, 21.0);
  static const SpringSpec dockClose = (420.0, 30.0);
  static const SpringSpec dockPop = (520.0, 16.0);

  // Toggle Switch (константы из его скрипта)
  static const SpringSpec togglePosition = (320.0, 18.0);
  static const SpringSpec toggleStretch = (300.0, 20.0);
}
