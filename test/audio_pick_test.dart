import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/async_utils.dart';
import 'package:trollmusic/core/utils/audio_pick.dart';

void main() {
  const opus160 = AudioFormat(url: 'a', mime: 'audio/webm; codecs="opus"', kbps: 160);
  const opus50 = AudioFormat(url: 'b', mime: 'audio/webm; codecs="opus"', kbps: 50);
  const aac128 = AudioFormat(url: 'c', mime: 'audio/mp4; codecs="mp4a.40.2"', kbps: 128);

  group('targetKbps', () {
    test('low/medium/high', () {
      expect(targetKbps(AudioQuality.low, onWifi: true), 64);
      expect(targetKbps(AudioQuality.medium, onWifi: true), 128);
      expect(targetKbps(AudioQuality.high, onWifi: false), isNull);
    });
    test('auto зависит от сети', () {
      expect(targetKbps(AudioQuality.auto, onWifi: true), isNull);
      expect(targetKbps(AudioQuality.auto, onWifi: false), 128);
    });
  });

  group('rankFormats', () {
    test('high выбирает максимальный битрейт', () {
      final r = rankFormats(const [opus50, opus160, aac128],
          quality: AudioQuality.high, onWifi: true);
      expect(r.first.url, 'a');
    });
    test('low выбирает ближайший к 64', () {
      final r = rankFormats(const [opus160, opus50, aac128],
          quality: AudioQuality.low, onWifi: true);
      expect(r.first.url, 'b');
    });
    test('aacOnly отфильтровывает opus', () {
      final r = rankFormats(const [opus160, aac128],
          quality: AudioQuality.high, onWifi: true, aacOnly: true);
      expect(r.map((f) => f.url), ['c']);
    });
    test('пустые ссылки игнорируются', () {
      final r = rankFormats(
        const [AudioFormat(url: '', mime: 'audio/mp4', kbps: 128)],
        quality: AudioQuality.auto,
        onWifi: true,
      );
      expect(r, isEmpty);
    });
  });

  test('parseContentRange', () {
    final r = parseContentRange('bytes 0-99/1000')!;
    expect((r.start, r.end, r.total), (0, 99, 1000));
    expect(parseContentRange('bytes 5-9/*')!.total, isNull);
    expect(parseContentRange('garbage'), isNull);
    expect(parseContentRange(null), isNull);
  });

  test('loudnessGain только ослабляет', () {
    expect(loudnessGain(null), 1.0);
    expect(loudnessGain(-3), 1.0);
    expect(loudnessGain(6), closeTo(0.501, 0.01));
    expect(loudnessGain(40), 0.25);
  });

  group('firstNonEmpty', () {
    test('возвращает первый успешный и игнорирует ошибки', () async {
      final r = await firstNonEmpty<String>([
        () async => throw StateError('x'),
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'slow';
        },
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 'fast';
        },
      ]);
      expect(r, 'fast');
    });
    test('null если ничего не нашлось', () async {
      final r = await firstNonEmpty<String>([() async => null]);
      expect(r, isNull);
    });
    test('firstNonEmptyList пропускает пустые списки', () async {
      final r = await firstNonEmptyList<int>([
        () async => <int>[],
        () async => [1, 2],
      ]);
      expect(r, [1, 2]);
    });
  });
}
