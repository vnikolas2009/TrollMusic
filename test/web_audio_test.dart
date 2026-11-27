import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/web_audio.dart';

void main() {
  group('browserTarget', () {
    test('ссылка остаётся ссылкой', () {
      expect(browserTarget('https://example.com/a?b=1').toString(), 'https://example.com/a?b=1');
    });

    test('домен без схемы получает https', () {
      expect(browserTarget('example.com/music').toString(), 'https://example.com/music');
    });

    test('обычный текст уходит в поиск', () {
      final uri = browserTarget('Queen Bohemian Rhapsody');
      expect(uri.host, 'duckduckgo.com');
      expect(uri.queryParameters['q'], 'Queen Bohemian Rhapsody');
    });

    test('пустой ввод открывает поисковик', () {
      expect(browserTarget('  ').host, 'duckduckgo.com');
    });
  });

  group('looksLikeAudioUrl', () {
    test('по расширению', () {
      expect(looksLikeAudioUrl(Uri.parse('https://a.b/x/song.MP3?t=1')), isTrue);
      expect(looksLikeAudioUrl(Uri.parse('https://a.b/page.html')), isFalse);
      expect(looksLikeAudioUrl(Uri.parse('blob:https://a.b/123')), isFalse);
    });
  });

  group('content type', () {
    test('расширение по типу', () {
      expect(audioExtensionFromContentType('audio/mpeg'), 'mp3');
      expect(audioExtensionFromContentType('audio/flac; charset=x'), 'flac');
      expect(audioExtensionFromContentType('text/html'), isNull);
    });

    test('допустимые ответы', () {
      expect(isDownloadableAudio('audio/mpeg'), isTrue);
      expect(isDownloadableAudio('application/octet-stream'), isTrue);
      expect(isDownloadableAudio('text/html; charset=utf-8'), isFalse);
      expect(isDownloadableAudio(null), isFalse);
    });
  });

  group('downloadFileName', () {
    test('из Content-Disposition', () {
      expect(
        downloadFileName(
          url: Uri.parse('https://a.b/dl?id=1'),
          contentDisposition: 'attachment; filename="Artist - Song.mp3"',
        ),
        'Artist - Song.mp3',
      );
    });

    test('filename* с кодированием', () {
      expect(
        downloadFileName(
          url: Uri.parse('https://a.b/dl'),
          contentDisposition: "attachment; filename*=UTF-8''%D0%9F%D0%B5%D1%81%D0%BD%D1%8F.flac",
        ),
        'Песня.flac',
      );
    });

    test('из пути ссылки', () {
      expect(
        downloadFileName(url: Uri.parse('https://a.b/files/My%20Track.m4a')),
        'My Track.m4a',
      );
    });

    test('без расширения берётся по типу, запрещённые символы убираются', () {
      expect(
        downloadFileName(
          url: Uri.parse('https://a.b/stream'),
          contentType: 'audio/flac',
          pageTitle: 'a:b',
        ),
        'stream.flac',
      );
      expect(
        downloadFileName(
          url: Uri.parse('https://a.b/'),
          pageTitle: 'AC/DC: Back?',
        ),
        'AC DC Back.mp3',
      );
    });

    test('пустое имя заменяется на track', () {
      expect(downloadFileName(url: Uri.parse('https://a.b/')), 'track.mp3');
    });
  });
}
