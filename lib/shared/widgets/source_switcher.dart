import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/source_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'press_scale.dart';

/// Переключатель источника каталога: горизонтальная лента «таблеток».
///
/// Выбранный пункт заливается цветом текста темы, у каждого источника своя
/// цветная точка (в духе «tab pill» / «segmented control»). Лента сама
/// прокручивается к выбранному пункту, поэтому не важно, сколько источников.
class SourceSwitcher extends StatefulWidget {
  const SourceSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final MusicSource selected;
  final ValueChanged<MusicSource> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  State<SourceSwitcher> createState() => _SourceSwitcherState();
}

class _SourceSwitcherState extends State<SourceSwitcher> {
  final Map<MusicSource, GlobalKey> _keys = {
    for (final source in MusicSource.values) source: GlobalKey(),
  };

  @override
  void didUpdateWidget(SourceSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[widget.selected]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: AppMotion.base,
        curve: AppMotion.emphasized,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: widget.padding,
      child: Row(
        children: [
          for (final source in MusicSource.values) ...[
            _SourcePill(
              key: _keys[source],
              source: source,
              selected: source == widget.selected,
              onTap: () {
                if (source == widget.selected) return;
                HapticFeedback.selectionClick();
                widget.onChanged(source);
              },
            ),
            if (source != MusicSource.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final MusicSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.emphasized,
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.press,
              width: selected ? 9 : 7,
              height: selected ? 9 : 7,
              decoration: BoxDecoration(
                color: source.color,
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: source.color.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ]
                    : const [],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.inverse : AppColors.textSecondary,
              ),
              child: Text(source.label),
            ),
          ],
        ),
      ),
    );
  }
}
