import 'package:flutter/material.dart';

/// Единый заголовок вкладки: крупный текст в верхней части экрана.
///
/// Не закрепляется и не имеет собственного фона — прокручивается вместе
/// с содержимым. Вместо текста можно передать [child] (например, логотип
/// на главной), отступы и высота у всех вкладок одинаковые.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, this.title, this.child, this.trailing})
      : assert(title != null || child != null);

  final String? title;
  final Widget? child;
  final Widget? trailing;

  static const padding = EdgeInsets.fromLTRB(20, 10, 8, 10);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: child ??
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                        height: 1.1,
                      ),
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
