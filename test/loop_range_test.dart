import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/loop_range.dart';

void main() {
  group('loopRangeForLine', () {
    test('от начала строки до начала следующей', () {
      final r = loopRangeForLine(
        lineTime: const Duration(seconds: 10),
        nextLineTime: const Duration(seconds: 14),
      );
      expect(r, LoopRange(const Duration(seconds: 10), const Duration(seconds: 14)));
    });

    test('сдвиг текста переводится во время аудио', () {
      // offset +500 мс: текст появляется на 0,5 с раньше аудио-времени строки
      final r = loopRangeForLine(
        lineTime: const Duration(seconds: 10),
        nextLineTime: const Duration(seconds: 14),
        offsetMs: 500,
      );
      expect(r!.start, const Duration(milliseconds: 9500));
      expect(r.end, const Duration(milliseconds: 13500));
    });

    test('начало не уходит в минус', () {
      final r = loopRangeForLine(
        lineTime: const Duration(milliseconds: 200),
        nextLineTime: const Duration(seconds: 4),
        offsetMs: 1000,
      );
      expect(r!.start, Duration.zero);
    });

    test('у последней строки 5 секунд, но не дальше конца трека', () {
      final open = loopRangeForLine(lineTime: const Duration(seconds: 60));
      expect(open!.end, const Duration(seconds: 65));

      final capped = loopRangeForLine(
        lineTime: const Duration(seconds: 60),
        trackDuration: const Duration(seconds: 63),
      );
      expect(capped!.end, const Duration(seconds: 63));
    });

    test('слишком короткий отрезок не повторяется', () {
      expect(
        loopRangeForLine(
          lineTime: const Duration(seconds: 10),
          nextLineTime: const Duration(milliseconds: 10200),
        ),
        isNull,
      );
    });
  });

  group('LoopRange', () {
    const r = LoopRange(Duration(seconds: 10), Duration(seconds: 14));

    test('reached срабатывает чуть раньше конца', () {
      expect(r.reached(const Duration(seconds: 13)), isFalse);
      expect(r.reached(const Duration(milliseconds: 13950)), isTrue);
      expect(r.reached(const Duration(seconds: 15)), isTrue);
    });

    test('contains: внутри отрезка и вне его', () {
      expect(r.contains(const Duration(seconds: 12)), isTrue);
      expect(r.contains(const Duration(seconds: 5)), isFalse);
      expect(r.contains(const Duration(seconds: 14)), isFalse);
    });
  });
}
