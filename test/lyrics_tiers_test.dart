import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/lyrics/asia_providers.dart';
import 'package:trollmusic/core/utils/lyrics_match.dart';
import 'package:trollmusic/services/lyrics/lyrics_service.dart';

void main() {
  const query = LyricsQuery(title: 'Song', artist: 'Band', durationSec: 200);

  LyricsCandidate cand(String source, {String? synced, String? plain, int dur = 200}) =>
      LyricsCandidate(
        title: 'Song',
        artist: 'Band',
        durationSec: dur,
        source: source,
        synced: synced,
        plain: plain,
      );

  test('enhanced LRC выигрывает у обычного LRC и текста', () {
    final best = pickByTier(query, [
      cand('plain', plain: 'text'),
      cand('lrc', synced: '[00:01.00]hello world'),
      cand('elrc', synced: '[00:01.00]<00:01.00>hello <00:01.50>world', dur: 203),
    ]);
    expect(best!.candidate.source, 'elrc');
    expect(best.tier, 3);
  });

  test('без enhanced побеждает построчный LRC', () {
    final best = pickByTier(query, [
      cand('plain', plain: 'text'),
      cand('lrc', synced: '[00:01.00]hello'),
    ]);
    expect(best!.candidate.source, 'lrc');
  });

  test('кандидат с другой длительностью отбрасывается', () {
    expect(pickByTier(query, [cand('x', plain: 't', dur: 400)]), isNull);
  });

  test('KRC превращается в enhanced LRC', () {
    final lrc = krcTextToEnhancedLrc(
      '[1000,2000]<0,500,0>Hel<500,700,0>lo <1200,800,0>world\n[3500,1000]<0,400,0>Bye',
    );
    expect(lrc, '[00:01.00]<00:01.00>Hel<00:01.50>lo <00:02.20>world\n[00:03.50]<00:03.50>Bye');
  });

  test('KRC без пословных меток даёт null', () {
    expect(krcTextToEnhancedLrc('[1000,2000]plain'), isNull);
  });

  group('замазанные слова и неточные таймкоды', () {
    test('looksCensored находит звёздочки в словах, но не сноски', () {
      expect(looksCensored('What the f*** is this'), isTrue);
      expect(looksCensored('Ты **** и с***а'), isTrue);
      expect(looksCensored('f*ck'), isTrue);
      expect(looksCensored('Обычный текст*'), isFalse);
      expect(looksCensored('Обычный текст без замен'), isFalse);
    });

    test('полный LRC выигрывает у enhanced с замазанными словами', () {
      final best = pickByTier(query, [
        cand('masked', synced: '[00:01.00]<00:01.00>what the <00:01.50>f***'),
        cand('clean', synced: '[00:01.00]what the fuck'),
      ]);
      expect(best!.candidate.source, 'clean');
    });

    test('замазанный синхронизированный текст лучше чистого без таймкодов', () {
      final best = pickByTier(query, [
        cand('masked', synced: '[00:01.00]what the f***'),
        cand('plain', plain: 'what the fuck'),
      ]);
      expect(best!.candidate.source, 'masked');
    });

    test('таймкоды другой версии трека не принимаются как точные', () {
      final best = pickByTier(query, [
        cand('shifted', synced: '[00:01.00]hello', dur: 193),
      ]);
      expect(best!.degraded, isTrue);
      expect(best.rank, 1);
    });

    test('точные таймкоды лучше таймкодов с расхождением', () {
      final best = pickByTier(query, [
        cand('shifted', synced: '[00:01.00]<00:01.00>hello', dur: 193),
        cand('exact', synced: '[00:01.00]hello', dur: 201),
      ]);
      expect(best!.candidate.source, 'exact');
      expect(best.degraded, isFalse);
    });
  });
}
