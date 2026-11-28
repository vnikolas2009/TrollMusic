/// Закладка встроенного браузера.
class BrowserBookmark {
  const BrowserBookmark(this.title, this.url);

  final String title;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is BrowserBookmark && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Готовые закладки: сайты с бесплатной и свободно лицензируемой музыкой,
/// откуда треки можно скачивать законно.
const defaultBookmarks = <BrowserBookmark>[
  BrowserBookmark('Jamendo', 'https://www.jamendo.com'),
  BrowserBookmark('Free Music Archive', 'https://freemusicarchive.org'),
  BrowserBookmark('Internet Archive', 'https://archive.org/details/audio'),
  BrowserBookmark('ccMixter', 'https://ccmixter.org'),
  BrowserBookmark('Pixabay Music', 'https://pixabay.com/music/'),
  BrowserBookmark('Musopen', 'https://musopen.org/music/'),
  BrowserBookmark('Incompetech', 'https://incompetech.com/music/royalty-free/music.html'),
];

const _separator = '\u{1F}';

/// Строка для хранения в настройках: «название␟адрес».
String encodeBookmark(BrowserBookmark b) => '${b.title}$_separator${b.url}';

/// Обратное к [encodeBookmark]; `null`, если строка повреждена.
BrowserBookmark? decodeBookmark(String raw) {
  final i = raw.indexOf(_separator);
  if (i <= 0) return null;
  final title = raw.substring(0, i).trim();
  final url = raw.substring(i + 1).trim();
  final uri = Uri.tryParse(url);
  if (title.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return BrowserBookmark(title, url);
}

/// Подпись закладки по заголовку страницы или хосту, не длиннее 24 знаков.
String bookmarkTitle(String? pageTitle, Uri url) {
  var title = (pageTitle ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isEmpty) title = url.host.replaceFirst(RegExp(r'^www\.'), '');
  return title.length > 24 ? '${title.substring(0, 23).trim()}…' : title;
}
