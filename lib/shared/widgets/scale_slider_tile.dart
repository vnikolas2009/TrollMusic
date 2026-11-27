import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'jelly_slider.dart';

/// Строка настройки с ползунком масштаба: название, значение в процентах и
/// тот же бегунок, что и в плеере.
class ScaleSliderTile extends StatelessWidget {
  const ScaleSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  static String percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                percent(value),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          JellyValueSlider(
            value: value,
            min: min,
            max: max,
            step: step,
            onChanged: onChanged,
            labelBuilder: percent,
          ),
        ],
      ),
    );
  }
}
