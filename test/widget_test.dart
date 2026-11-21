import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/formatters.dart';
import 'package:trollmusic/core/utils/lrc_parser.dart';

void main() {
  test('formats duration', () {
    expect(formatDuration(const Duration(seconds: 75)), '1:15');
    expect(formatDuration(const Duration(minutes: 62, seconds: 5)), '1:02:05');
  });

  test('parses synced lrc', () {
    final lyrics = LrcParser.parse('[ar:Artist]\n[00:01.50]First\n[00:03.00]Second');
    expect(lyrics.synced, isTrue);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines.first.time, const Duration(milliseconds: 1500));
    expect(lyrics.indexAt(const Duration(seconds: 4)), 1);
  });
}

