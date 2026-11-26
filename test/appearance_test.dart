import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/theme/app_fonts.dart';
import 'package:trollmusic/core/theme/appearance.dart';

void main() {
  tearDown(() {
    AppAppearance.effects = EffectsLevel.defaultLevel;
    AppAppearance.coverShape = CoverShape.defaultShape;
  });

  group('индексы настроек', () {
    test('byIndex ограничивает значения и берёт умолчание для null', () {
      expect(AnimationMode.byIndex(null), AnimationMode.smooth);
      expect(AnimationMode.byIndex(-5), AnimationMode.values.first);
      expect(AnimationMode.byIndex(99), AnimationMode.values.last);
      expect(EffectsLevel.byIndex(null), EffectsLevel.normal);
      expect(CoverShape.byIndex(null), CoverShape.rounded);
      expect(CoverShape.byIndex(99), CoverShape.soft);
    });

    test('индексы в хранилище совпадают со значениями по умолчанию', () {
      // settings.dart хранит эти числа как значения по умолчанию.
      expect(AnimationMode.defaultMode.index, 0);
      expect(EffectsLevel.defaultLevel.index, 2);
      expect(CoverShape.defaultShape.index, 1);
    });
  });

  group('анимации', () {
    test('быстрые режимы короче по времени, спокойные без отскока', () {
      expect(AnimationMode.smooth.timeDilation, 1.0);
      expect(AnimationMode.fast.timeDilation, lessThan(1.0));
      expect(AnimationMode.minimal.timeDilation, lessThan(AnimationMode.fast.timeDilation));
      expect(AnimationMode.smooth.reduceMotion, isFalse);
      expect(AnimationMode.fast.reduceMotion, isFalse);
      expect(AnimationMode.calm.reduceMotion, isTrue);
      expect(AnimationMode.minimal.reduceMotion, isTrue);
    });

    test('timeDilation всегда положителен', () {
      for (final m in AnimationMode.values) {
        expect(m.timeDilation, greaterThan(0));
      }
    });
  });

  group('эффекты', () {
    test('при «Выкл» тени нет', () {
      AppAppearance.effects = EffectsLevel.off;
      expect(AppAppearance.shadows(blur: 20, offset: const Offset(0, 4)), isEmpty);
    });

    test('сильнее эффекты — плотнее и шире тень', () {
      AppAppearance.effects = EffectsLevel.soft;
      final soft = AppAppearance.shadows(blur: 20, offset: const Offset(0, 4)).single;
      AppAppearance.effects = EffectsLevel.vivid;
      final vivid = AppAppearance.shadows(blur: 20, offset: const Offset(0, 4)).single;

      expect(vivid.blurRadius, greaterThan(soft.blurRadius));
      expect(vivid.color.a, greaterThanOrEqualTo(soft.color.a));
      expect(vivid.color.a, lessThanOrEqualTo(1.0));
    });
  });

  group('форма обложек', () {
    test('радиус зависит от формы', () {
      AppAppearance.coverShape = CoverShape.square;
      expect(AppAppearance.coverRadius(12), 0);
      AppAppearance.coverShape = CoverShape.rounded;
      expect(AppAppearance.coverRadius(12), 12);
      AppAppearance.coverShape = CoverShape.soft;
      expect(AppAppearance.coverRadius(12), greaterThan(12));
    });
  });

  group('толщина шрифта', () {
    test('familyFor: обычная толщина — базовое семейство', () {
      expect(BuiltInFont.inter.familyFor(BuiltInFont.defaultWeightLevel), 'Inter');
      expect(BuiltInFont.inter.familyFor(0), 'Inter-w0');
      expect(BuiltInFont.manrope.familyFor(3), 'Manrope-w3');
      expect(BuiltInFont.manrope.familyFor(99), 'Manrope-w3');
      expect(BuiltInFont.manrope.familyFor(-4), 'Manrope-w0');
    });

    test('pubspec.yaml объявляет семейство для каждого уровня', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final font in BuiltInFont.all) {
        for (var level = 0; level < BuiltInFont.weightLevels.length; level++) {
          expect(
            pubspec.contains('- family: ${font.familyFor(level)}\n'),
            isTrue,
            reason: 'нет семейства ${font.familyFor(level)}',
          );
        }
      }
    });
  });
}
