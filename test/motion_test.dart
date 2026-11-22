import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/motion/rubber.dart';
import 'package:trollmusic/core/motion/spring.dart';
import 'package:trollmusic/core/utils/read_along.dart';
import 'package:trollmusic/shared/widgets/read_along_text.dart';
import 'package:trollmusic/shared/widgets/spring_switch.dart';

void main() {
  group('Spring', () {
    test('полунеявный Эйлер: сначала скорость, потом позиция', () {
      final s = Spring(0, 100, 0)..t = 1;
      s.step(0.1);
      expect(s.v, closeTo(10, 1e-9));
      expect(s.x, closeTo(1, 1e-9));
    });

    test('сходится к цели', () {
      final s = Spring(0, 320, 18)..t = 1;
      for (var i = 0; i < 240 * 4; i++) {
        s.step(1 / 240);
      }
      expect(s.x, closeTo(1, 1e-3));
      expect(s.atRest, isTrue);
    });

    test('токен 320/18 даёт перелёт, критическое демпфирование — нет', () {
      double peak(bool reduce) {
        final s = Spring(0)..tune(SpringTokens.togglePosition, reduceMotion: reduce);
        s.t = 1;
        var max = 0.0;
        for (var i = 0; i < 240 * 3; i++) {
          s.step(1 / 240);
          max = math.max(max, s.x);
        }
        return max;
      }

      expect(peak(false), greaterThan(1.05));
      expect(peak(true), lessThanOrEqualTo(1.01));
    });

    test('reduceMotion ставит демпфирование 2·√k', () {
      final s = Spring(0)..tune((400.0, 10.0), reduceMotion: true);
      expect(s.c, closeTo(2 * math.sqrt(400), 1e-9));
      expect(criticalDamping(100), 20);
    });

    test('frameDelta обрезает паузы и отрицательные значения', () {
      expect(
        frameDelta(const Duration(seconds: 3), const Duration(seconds: 1)),
        closeTo(1 / 30, 1e-12),
      );
      expect(frameDelta(const Duration(milliseconds: 5), const Duration(milliseconds: 9)), 0);
      expect(
        frameDelta(const Duration(milliseconds: 26), const Duration(milliseconds: 10)),
        closeTo(0.016, 1e-9),
      );
    });

    test('stepSprings делит шаг на подшаги', () {
      final a = Spring(0, 900, 50)..t = 1;
      final b = Spring(0, 900, 50)..t = 1;
      stepSprings([a], 0.02);
      for (var i = 0; i < 4; i++) {
        b.step(0.02 / 4);
      }
      expect(a.x, closeTo(b.x, 1e-12));
      expect(a.v, closeTo(b.v, 1e-12));
    });

    test('токены совпадают с tokens.css', () {
      expect(SpringTokens.dockLead, (640.0, 38.0));
      expect(SpringTokens.dockTrail, (150.0, 16.0));
      expect(SpringTokens.dockDragLead, (1100.0, 56.0));
      expect(SpringTokens.dockOpenH, (230.0, 21.0));
      expect(SpringTokens.dockClose, (420.0, 30.0));
      expect(SpringTokens.dockPop, (520.0, 16.0));
    });
  });

  group('rubberBand', () {
    test('внутри диапазона не меняет значение', () {
      expect(rubberBand(50, 10, 90), 50);
      expect(rubberBand(10, 10, 90), 10);
      expect(rubberBand(90, 10, 90), 90);
    });

    test('за краем сопротивляется и не уходит дальше предела', () {
      final a = rubberBand(100, 10, 90);
      final b = rubberBand(300, 10, 90);
      expect(a, greaterThan(90));
      expect(b, greaterThan(a));
      expect(b, lessThan(90 + 46));
      expect(rubberBand(100000, 10, 90), lessThan(90 + 46));
    });

    test('симметрично с обеих сторон', () {
      expect(10 - rubberBand(-40, 10, 90), closeTo(rubberBand(140, 10, 90) - 90, 1e-9));
    });
  });

  group('Read along', () {
    test('splitWords хранит границы слов и пропускает двойные пробелы', () {
      final words = splitWords('Make  the thing');
      expect(words.map((w) => w.text), ['Make', 'the', 'thing']);
      expect(words[1].start, 6);
      expect(words[1].end, 9);
      expect(words[2].length, 5);
      expect(splitWords(''), isEmpty);
      expect(splitWords('   '), isEmpty);
    });

    test('wordIndexForProgress: границы и пустой текст', () {
      final words = splitWords('one two three four');
      expect(wordIndexForProgress(words, 0), 0);
      expect(wordIndexForProgress(words, -3), 0);
      expect(wordIndexForProgress(words, 1), words.length - 1);
      expect(wordIndexForProgress(words, 9), words.length - 1);
      expect(wordIndexForProgress(const [], 0.5), -1);
    });

    test('индекс не убывает, а длинные слова занимают больше времени', () {
      final words = splitWords('a bbbbbbbbbb');
      expect(wordIndexForProgress(words, 0.2), 0);
      expect(wordIndexForProgress(words, 0.4), 1);

      final many = splitWords('make the thing then make it simple');
      var last = 0;
      for (var i = 0; i <= 100; i++) {
        final index = wordIndexForProgress(many, i / 100);
        expect(index, greaterThanOrEqualTo(last));
        last = index;
      }
      expect(last, many.length - 1);
    });

    test('wordDwell — формула из исходника', () {
      expect(wordDwell(0), closeTo(0.2, 1e-12));
      expect(wordDwell(10), closeTo(0.55, 1e-12));
    });
  });

  group('виджеты', () {
    testWidgets('SpringSwitch переключается по тапу и отключается', (tester) async {
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => SpringSwitch(
                  value: value,
                  semanticLabel: 'Тест',
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SpringSwitch));
      await tester.pump(const Duration(milliseconds: 600));
      expect(value, isTrue);

      await tester.tap(find.byType(SpringSwitch));
      await tester.pump(const Duration(milliseconds: 600));
      expect(value, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ReadAlongText строится и переживает смену слова', (tester) async {
      Widget app(double progress) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ReadAlongText(
                text: 'Сделай вещь, потом сделай её простой',
                progress: progress,
                style: const TextStyle(fontSize: 28, color: Colors.white),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ReadAlongText), findsOneWidget);

      for (final p in [0.3, 0.6, 1.0, 0.0]) {
        await tester.pumpWidget(app(p));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
