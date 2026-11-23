import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/lyrics/external_lyrics.dart';

void main() {
  test('htmlToText: переносы, теги и сущности', () {
    expect(
      htmlToText('Hello<br/>wor<i>ld</i> &amp; you<br><br><br><br>Bye'),
      'Hello\nworld & you\n\nBye',
    );
  });

  test('extractGeniusLyrics собирает блоки с вложенными div', () {
    const html = '<div class="x"><div data-lyrics-container="true" class="a">'
        '[Verse]<br/>Line one<div>inner</div><br/>Line two</div>'
        '<div data-lyrics-container="true">Second</div></div>';
    final text = extractGeniusLyrics(html);
    expect(text, contains('Line one'));
    expect(text, contains('Line two'));
    expect(text, contains('Second'));
    expect(extractGeniusLyrics('<html></html>'), isNull);
  });

  test('pickGeniusUrl берёт подходящий хит, иначе первый', () {
    final json = {
      'response': {
        'hits': [
          {
            'result': {
              'url': 'https://genius.com/other',
              'title': 'Другая',
              'primary_artist': {'name': 'Кто-то'},
            },
          },
          {
            'result': {
              'url': 'https://genius.com/right',
              'title': 'Моя песня',
              'primary_artist': {'name': 'Артист'},
            },
          },
        ],
      },
    };
    expect(
      pickGeniusUrl(json, artist: 'Артист, Гость', title: 'Моя песня'),
      'https://genius.com/right',
    );
    expect(
      pickGeniusUrl(json, artist: 'Никто', title: 'Нет такой'),
      'https://genius.com/other',
    );
    expect(pickGeniusUrl(null, artist: 'a', title: 'b'), isNull);
  });

  test('extractLrcFromHtml берёт строки с таймкодами, иначе null', () {
    const html = '<div>[00:01.00] one<br/>[00:05.50] two<br/>'
        'noise<br/>[01:02.3] three<br/></div>';
    expect(
      extractLrcFromHtml(html),
      '[00:01.00] one\n[00:05.50] two\n[01:02.3] three',
    );
    expect(extractLrcFromHtml('<html>Just a moment...</html>'), isNull);
    expect(extractLrcFromHtml('<p>[00:01.00] only one</p>'), isNull);
  });

  test('pickLyricsifyPath выбирает ссылку по названию', () {
    const html = '<a href="/lyrics/other/song">x</a>'
        '<a href="/lyrics/coldplay/yellow">y</a>';
    expect(
      pickLyricsifyPath(html, artist: 'Coldplay', title: 'Yellow'),
      '/lyrics/coldplay/yellow',
    );
    expect(
      pickLyricsifyPath(html, artist: 'Nobody', title: 'Nothing'),
      '/lyrics/other/song',
    );
    expect(pickLyricsifyPath('<p/>', artist: 'a', title: 'b'), isNull);
  });
}
