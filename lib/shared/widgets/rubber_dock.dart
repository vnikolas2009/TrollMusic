import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/motion/rubber.dart';
import '../../core/motion/spring.dart';
import '../../core/theme/app_colors.dart';

/// Вкладка дока: иконка и подпись (подпись нужна для доступности).
class RubberDockTab {
  const RubberDockTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// «Rubber dock»: панель вкладок, у которой пилюля тянется, как резина,
/// а нажатие на активную вкладку раскрывает док в карточку.
///
/// Края пилюли — две пружины: передний край жёсткий, задний ленивый,
/// поэтому между вкладками она растягивается. Пилюлю можно тащить пальцем:
/// за крайними вкладками она сопротивляется, как резинка, и возвращается.
/// Иконки поверх пилюли перекрашиваются ровно там, где она находится.
///
/// Виджет занимает по высоте место под раскрытую карточку
/// (`панель + высота дока`) и прижат к низу: размещайте его в `Stack`
/// у нижнего края экрана. Пустая область над доком касания не перехватывает.
class RubberDock extends StatefulWidget {
  RubberDock({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    this.panelBuilder,
    this.panelHeight = 260,
    this.expandedWidth = 340,
  }) : assert(tabs.length >= 2, 'Для дока нужно минимум две вкладки');

  final List<RubberDockTab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Содержимое карточки для вкладки [index]. Без него док не раскрывается.
  final Widget Function(BuildContext context, int index)? panelBuilder;

  final double panelHeight;
  final double expandedWidth;

  @override
  State<RubberDock> createState() => _RubberDockState();
}

class _RubberDockState extends State<RubberDock>
    with SingleTickerProviderStateMixin {
  static const _tab = 56.0;
  static const _gap = 4.0;
  static const _inset = 6.0;

  int get _n => widget.tabs.length;
  double get _tabsWidth => _n * _tab + (_n - 1) * _gap;
  double get _colWidth => _tabsWidth + _inset * 2;
  static const _colHeight = _tab + _inset * 2;

  double _cx(int i) => _tab / 2 + i * (_tab + _gap);

  late final Spring _left = Spring(_cx(widget.selected) - _tab / 2);
  late final Spring _right = Spring(_cx(widget.selected) + _tab / 2);
  late final Spring _width = Spring(_tab + _inset * 2, 260, 20);
  late final Spring _height = Spring(_colHeight, 400, 34);
  final Spring _nudge = Spring(0, 300, 18);
  late final List<Spring> _pops = List.generate(
    _n,
    (_) => Spring(1, SpringTokens.dockPop.$1, SpringTokens.dockPop.$2),
  );
  late final List<Spring> _all = [
    _left,
    _right,
    _width,
    _height,
    _nudge,
    ..._pops,
  ];
  late final SpringLoop _loop = SpringLoop(this, _frame);

  late int _active = widget.selected;
  bool _expanded = false;
  bool _intro = false;
  double _clock = 0;
  double _available = 400;
  bool _reduceMotion = false;

  // жест перетаскивания
  bool _dragging = false;
  int _dragDir = 0;
  double _lastX = 0;

  @override
  void initState() {
    super.initState();
    _loop.start();
  }

  @override
  void didUpdateWidget(RubberDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != _active) _select(widget.selected, notify: false);
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  void _tune(Spring spring, SpringSpec spec) =>
      spring.tune(spec, reduceMotion: _reduceMotion);

  double get _expandedWidth =>
      math.min(widget.expandedWidth, _available - 24)
          .clamp(_colWidth, 4000.0)
          .toDouble();

  void _moveTo(double center, int dir, {bool drag = false}) {
    final lead = drag ? SpringTokens.dockDragLead : SpringTokens.dockLead;
    final trail = drag ? SpringTokens.dockDragTrail : SpringTokens.dockTrail;
    if (dir == 0) {
      _tune(_left, (600.0, 44.0));
      _tune(_right, (600.0, 44.0));
    } else {
      _tune(_left, dir > 0 ? trail : lead);
      _tune(_right, dir > 0 ? lead : trail);
    }
    _left.t = center - _tab / 2;
    _right.t = center + _tab / 2;
  }

  void _select(int index, {int? dir, bool notify = true}) {
    final i = index.clamp(0, _n - 1).toInt();
    final direction =
        dir ?? (_cx(i) - (_left.x + _right.x) / 2).sign.toInt();
    _moveTo(_cx(i), direction);

    final previous = _active;
    _active = i;
    _pops[i].v -= 3.2;

    if (_expanded && previous != i) {
      // карточка перестраивается под новую вкладку
      _tune(_height, (260.0, 20.0));
      _height.t = _colHeight + widget.panelHeight;
    }
    if (previous != i) HapticFeedback.selectionClick();
    if (notify && previous != i) widget.onSelected(i);
    if (notify && mounted) setState(() {});
  }

  void _setExpanded(bool value) {
    if (value == _expanded) return;
    if (value && widget.panelBuilder == null) return;
    _expanded = value;

    if (value) {
      _width.t = _expandedWidth;
      _height.t = _colHeight + widget.panelHeight;
      // ширина садится первой, высота перелетает позже
      _tune(_width, SpringTokens.dockOpenW);
      _tune(_height, SpringTokens.dockOpenH);
    } else {
      _width.t = _colWidth;
      _height.t = _colHeight;
      const close = SpringTokens.dockClose;
      _tune(_width, (close.$1 * 0.72, close.$2 * 0.66));
      _tune(_height, close);
    }
    _pops[_active].v -= 2.4;
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  void _frame(double dt) {
    _clock += dt;
    if (!_intro && _clock > 0.35) {
      // вступление: одна пилюля вырастает в док
      _intro = true;
      _width.t = _colWidth;
      _tune(_width, (220.0, 15.0));
    }
    stepSprings(_all, dt);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- жесты

  void _dragStart(DragStartDetails d) {
    _dragging = true;
    _dragDir = 0;
    _lastX = d.localPosition.dx + _nudge.x;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    // координата относительно ненарисованного сдвига дока, как в оригинале
    final raw = d.localPosition.dx + _nudge.x;
    final delta = raw - _lastX;
    _lastX = raw;
    if (delta.abs() > 0.5) _dragDir = delta.sign.toInt();

    final first = _cx(0), last = _cx(_n - 1);
    final center = rubberBand(raw, first, last);
    _moveTo(center, _dragDir, drag: true);
    _nudge.t = (center - center.clamp(first, last)) * 0.35;
  }

  void _dragEnd(DragEndDetails _) {
    if (!_dragging) return;
    _dragging = false;
    final center = (_left.t + _right.t) / 2;
    _nudge.t = 0;
    final index =
        ((center - _cx(0)) / (_tab + _gap) + _dragDir * 0.18).round();
    _select(index, dir: _dragDir);
  }

  void _tapUp(TapUpDetails d) {
    final x = d.localPosition.dx;
    final i = (x / (_tab + _gap)).floor().clamp(0, _n - 1).toInt();
    if (i == _active) {
      _setExpanded(!_expanded);
    } else {
      _select(i);
    }
  }

  // ---------------------------------------------------------------- вид

  Widget _iconRow({required Color color, required bool withSemantics}) {
    return Row(
      children: [
        for (var i = 0; i < _n; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          SizedBox(
            width: _tab,
            height: _tab,
            child: Center(
              child: Transform.scale(
                scale: _pops[i].x,
                child: withSemantics
                    ? Semantics(
                        button: true,
                        selected: i == _active,
                        label: widget.tabs[i].label,
                        child: Icon(widget.tabs[i].icon, size: 22, color: color),
                      )
                    : Icon(widget.tabs[i].icon, size: 22, color: color),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _available =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 400;

        final w = _width.x;
        final h = math.max(_height.x, 40.0);
        final open =
            ((h - _colHeight) / widget.panelHeight).clamp(0.0, 1.0).toDouble();
        // высота мчится вверх, ширина чуть «поддаётся»
        final give = (-_height.v / 9000).clamp(-0.04, 0.04).toDouble();
        final radius = math.min(h / 2, 34 - 8 * open);
        final dockWidth = w * (1 + give);

        var l = _left.x, r = _right.x;
        if (r < l) {
          final swap = l;
          l = r;
          r = swap;
        }
        // Пилюля всегда остаётся внутри «внутренней рамки» дока: между ней
        // и краем серого овала сохраняется отступ [_inset]. При перелёте
        // пружин или резиновом оттягивании она упирается в рамку, не меняя
        // ширину, поэтому края остаются скруглёнными и не обрезаются.
        final pillWidth = math.min(math.max(r - l, 24.0), _tabsWidth);
        l = l.clamp(0.0, _tabsWidth - pillWidth).toDouble();
        // площадь пилюли сохраняется: растянулась — стала ниже, но не выше
        // высоты вкладки
        final pillHeight =
            _tab * (1 / math.sqrt(pillWidth / _tab)).clamp(0.66, 1.0);
        final pillTop = (_tab - pillHeight) / 2;
        final pillRect = Rect.fromLTWH(l, pillTop, pillWidth, pillHeight);

        final panel = widget.panelBuilder;

        return SizedBox(
          height: _colHeight + widget.panelHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TapRegion(
              onTapOutside: (_) {
                if (_expanded) _setExpanded(false);
              },
              child: Transform.translate(
                offset: Offset(_nudge.x, 0),
                child: Container(
                  width: dockWidth,
                  height: h,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Stack(
                    children: [
                      if (panel != null && open > 0.01)
                        Positioned(
                          left: (dockWidth - _expandedWidth) / 2,
                          top: 0,
                          width: _expandedWidth,
                          height: widget.panelHeight,
                          child: IgnorePointer(
                            ignoring: !_expanded,
                            child: AnimatedOpacity(
                              opacity: _expanded ? 1 : 0,
                              duration: const Duration(milliseconds: 220),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                switchInCurve: Curves.easeOutCubic,
                                child: KeyedSubtree(
                                  key: ValueKey(_active),
                                  child: panel(context, _active),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: (dockWidth - _tabsWidth) / 2,
                        bottom: _inset,
                        width: _tabsWidth,
                        height: _tab,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: _tapUp,
                          onHorizontalDragStart: _dragStart,
                          onHorizontalDragUpdate: _dragUpdate,
                          onHorizontalDragEnd: _dragEnd,
                          child: Stack(
                            children: [
                              _iconRow(
                                color: AppColors.textSecondary,
                                withSemantics: true,
                              ),
                              Positioned.fromRect(
                                rect: pillRect,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.textPrimary,
                                    borderRadius:
                                        BorderRadius.circular(pillHeight / 2),
                                  ),
                                ),
                              ),
                              // тёмный слой иконок обрезан по пилюле:
                              // иконки меняют цвет ровно там, где она сейчас
                              IgnorePointer(
                                child: ExcludeSemantics(
                                  child: ClipPath(
                                    clipper: _PillClipper(pillRect),
                                    child: _iconRow(
                                      color: AppColors.inverse,
                                      withSemantics: false,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PillClipper extends CustomClipper<Path> {
  const _PillClipper(this.rect);

  final Rect rect;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
    );

  @override
  bool shouldReclip(_PillClipper old) => old.rect != rect;
}
