import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/lrc_parser.dart';

void main() {
  group('enhanced LRC', () {
    const enhanced =
        '[00:10.00]<00:10.00>Hello <00:10.50>dark <00:11.20>world<00:12.00>\n'
        '[00:13.00]<00:13.00>Next <00:13.40>line';

    test('detects word timing', () {
      expect(LrcParser.hasWordTiming(enhanced), isTrue);
      expect(LrcParser.hasWordTiming('[00:10.00]Plain'), isFalse);
      expect(LrcParser.looksSynced(enhanced), isTrue);
    });

    test('parses words with start and end', () {
      final lyrics = LrcParser.parse(enhanced);
      expect(lyrics.synced, isTrue);
      expect(lyrics.lines.length, 2);

      final first = lyrics.lines.first;
      expect(first.text, 'Hello dark world');
      expect(first.hasWordTiming, isTrue);
      expect(first.words.map((w) => w.text), ['Hello', 'dark', 'world']);
      expect(first.words[1].start, const Duration(milliseconds: 10500));
      expect(first.words[0].end, const Duration(milliseconds: 10500));
      expect(first.words.last.end, const Duration(seconds: 12));
    });

    test('word index follows playback position', () {
      final line = LrcParser.parse(enhanced).lines.first;
      expect(line.wordIndexAt(const Duration(seconds: 9)), -1);
      expect(line.wordIndexAt(const Duration(milliseconds: 10600)), 1);
      expect(line.wordIndexAt(const Duration(seconds: 12)), 2);
    });

    test('line without line stamp but with word stamps uses first word time', () {
      final lyrics = LrcParser.parse('<00:05.00>Only <00:05.50>words');
      expect(lyrics.synced, isTrue);
      expect(lyrics.lines.single.time, const Duration(seconds: 5));
      expect(lyrics.lines.single.text, 'Only words');
    });

    test('multiple stamps on one line produce several lines', () {
      final lyrics = LrcParser.parse('[00:05.00][00:20.00]Chorus');
      expect(lyrics.lines.map((l) => l.time), [
        const Duration(seconds: 5),
        const Duration(seconds: 20),
      ]);
    });

    test('offset tag shifts lines earlier when positive', () {
      final lyrics = LrcParser.parse('[offset:500]\n[00:10.00]Line');
      expect(lyrics.lines.single.time, const Duration(milliseconds: 9500));
    });

    test('reads title and artist tags', () {
      final meta = LrcParser.readMeta('[ti:Song]\n[ar:Band]\n[00:01.00]x');
      expect(meta.title, 'Song');
      expect(meta.artist, 'Band');
      expect(meta.album, isNull);
    });

    test('toLrc round-trips enhanced lines', () {
      final lyrics = LrcParser.parse(enhanced);
      final back = LrcParser.parse(LrcParser.toLrc(lyrics));
      expect(back.lines.length, lyrics.lines.length);
      expect(back.lines.first.words.length, 3);
      expect(back.lines.first.words[1].start, const Duration(milliseconds: 10500));
    });

    test('handles BOM and Windows line endings', () {
      final lyrics = LrcParser.parse('﻿[00:01.00]One\r\n[00:02.00]Two\r\n');
      expect(lyrics.lines.length, 2);
    });
  });
}
