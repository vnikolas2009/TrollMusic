import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/browser_bookmarks.dart';

void main() {
  test('готовые закладки: у каждой есть название и https-адрес, без повторов', () {
    for (final b in defaultBookmarks) {
      expect(b.title, isNotEmpty);
      expect(Uri.parse(b.url).scheme, 'https');
    }
    expect(defaultBookmarks.map((b) => b.url).toSet().length, defaultBookmarks.length);
  });

  test('сохранение и чтение закладки', () {
    const b = BrowserBookmark('Мой сайт', 'https://example.com/music?a=1');
    expect(decodeBookmark(encodeBookmark(b)), b);
    expect(decodeBookmark(encodeBookmark(b))?.title, 'Мой сайт');
  });

  test('повреждённые строки отбрасываются', () {
    expect(decodeBookmark(''), isNull);
    expect(decodeBookmark('без разделителя'), isNull);
    expect(decodeBookmark('Имя\u{1F}не адрес'), isNull);
    expect(decodeBookmark('\u{1F}https://a.b'), isNull);
  });

  test('подпись: заголовок страницы или хост, не длиннее 24 знаков', () {
    final url = Uri.parse('https://www.example.com/x');
    expect(bookmarkTitle('  My   Music ', url), 'My Music');
    expect(bookmarkTitle('', url), 'example.com');
    expect(bookmarkTitle(null, url), 'example.com');
    expect(bookmarkTitle('a' * 40, url).length, 24);
  });
}
