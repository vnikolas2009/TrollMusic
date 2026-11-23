import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Надпись «TrollMusic»: «Troll» плотным цветом, «Music» — акцентным
/// градиентом, по которому медленно проходит блик.
class BrandWordmark extends StatefulWidget {
  const BrandWordmark({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  State<BrandWordmark> createState() => _BrandWordmarkState();
}

class _BrandWordmarkState extends State<BrandWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // При «Убрать анимацию» блик стоит на месте.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.fontSize;
    final base = TextStyle(
      fontSize: size,
      height: 1.1,
      letterSpacing: -0.6,
    );
    final accent = AppColors.accent;

    return Semantics(
      label: 'TrollMusic',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Troll',
            style: base.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => LinearGradient(
                  colors: [
                    accent,
                    Color.lerp(accent, Colors.white, 0.75)!,
                    accent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  // блик ездит слева направо за пределы слова и обратно в начало
                  transform: _SlideGradient(-1 + 3 * t),
                ).createShader(rect),
                child: child,
              );
            },
            child: Text(
              'Music',
              style: base.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.offset);

  final double offset;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * offset, 0, 0);
}
