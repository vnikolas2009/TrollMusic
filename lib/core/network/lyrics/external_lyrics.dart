import 'package:dio/dio.dart';

import '../http_client.dart';

/// Откуда брать текст. LRCLIB отдаёт синхронизированный (LRC), остальные —
/// обычный текст без таймкодов.
enum LyricsSource {
  lrclib('LRCLIB', 'синхронизированные тексты'),
  lyricsOvh('Lyrics.ovh', 'обычный текст, без ключа'),
  genius('Genius', 'нужен токен в настройках'),
  lyricsify('Lyricsify', 'тексты с таймкодами (LRC)');

  const LyricsSource(this.label, this.hint);

  final String label;
  final String hint;
}

/// Тексты из Lyrics.ovh и Genius. Оба источника возвращают обычный текст.
class ExternalLyricsClient {
  ExternalLyricsClient({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  Future<String?> lyricsOvh({
    required String artist,
    required String title,
  }) async {
    if (artist.trim().isEmpty || title.trim().isEmpty) return null;
    try {
      final uri = Uri.https(
        'api.lyrics.ovh',
        '/v1/${Uri.encodeComponent(artist.trim())}/${Uri.encodeComponent(title.trim())}',
      );
      final response = await _dio.getUri<dynamic>(uri);
      if (response.statusCode != 200) return null;
      final data = response.data;
      final text = data is Map ? data['lyrics'] as String? : null;
      final clean = text?.replaceAll('\r\n', '\n').trim();
      return clean == null || clean.isEmpty ? null : clean;
    } on DioException {
      return null;
    }
  }

  /// Lyricsify: поиск по сайту и разбор страницы песни. Своего API у сайта
  /// нет, поэтому разбор «по месту»: ищем строки с таймкодами `[мм:сс.хх]`.
  /// Если сайт отдал защитную страницу, вернётся `null`.
  Future<String?> lyricsify({
    required String artist,
    required String title,
  }) async {
    try {
      final search = await _dio.getUri<String>(
        Uri.https('www.lyricsify.com', '/search', {'q': '$artist $title'.trim()}),
        options: _htmlOptions,
      );
      if (search.statusCode != 200) return null;
      final path =
          pickLyricsifyPath(search.data ?? '', artist: artist, title: title);
      if (path == null) return null;
      return lyricsifyUrl('https://www.lyricsify.com$path');
    } on DioException {
      return null;
    }
  }

  /// Импорт по готовой ссылке на страницу песни Lyricsify.
  Future<String?> lyricsifyUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.host.endsWith('lyricsify.com')) return null;
    try {
      final page = await _dio.getUri<String>(
        uri.replace(scheme: 'https'),
        options: _htmlOptions,
      );
      if (page.statusCode != 200) return null;
      return extractLrcFromHtml(page.data ?? '');
    } on DioException {
      return null;
    }
  }

  static final _htmlOptions = Options(
    responseType: ResponseType.plain,
    headers: {'accept': 'text/html'},
  );

  /// Поиск через официальный API Genius (нужен клиентский токен), затем
  /// разбор страницы песни. Genius иногда отдаёт страницу-заглушку ботам,
  /// тогда вернётся `null`.
  Future<String?> genius({
    required String token,
    required String artist,
    required String title,
  }) async {
    if (token.trim().isEmpty) return null;
    try {
      final search = await _dio.getUri<dynamic>(
        Uri.https('api.genius.com', '/search', {'q': '$artist $title'.trim()}),
        options: Options(
          headers: {'authorization': 'Bearer ${token.trim()}'},
        ),
      );
      final url = pickGeniusUrl(search.data, artist: artist, title: title);
      if (url == null) return null;

      final page = await _dio.getUri<String>(
        Uri.parse(url),
        options: Options(
          responseType: ResponseType.plain,
          headers: {'accept': 'text/html'},
        ),
      );
      if (page.statusCode != 200) return null;
      return extractGeniusLyrics(page.data ?? '');
    } on DioException {
      return null;
    }
  }
}

String _norm(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

/// Выбирает из ответа поиска Genius страницу, подходящую по названию.
String? pickGeniusUrl(
  dynamic json, {
  required String artist,
  required String title,
}) {
  dynamic hits;
  if (json is Map) {
    final response = json['response'];
    if (response is Map) hits = response['hits'];
  }
  if (hits is! List) return null;

  final wantTitle = _norm(title);
  final wantArtist = _norm(artist.split(',').first);
  String? fallback;

  for (final hit in hits) {
    final result = hit is Map ? hit['result'] : null;
    if (result is! Map) continue;
    final url = result['url'] as String?;
    if (url == null) continue;
    fallback ??= url;

    final gotTitle = _norm(result['title'] as String? ?? '');
    final gotArtist =
        _norm((result['primary_artist'] as Map?)?['name'] as String? ?? '');
    final titleOk = gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle);
    final artistOk = wantArtist.isEmpty ||
        gotArtist.contains(wantArtist) ||
        wantArtist.contains(gotArtist);
    if (titleOk && artistOk) return url;
  }
  return fallback;
}

/// Достаёт текст из HTML страницы Genius (блоки `data-lyrics-container`).
String? extractGeniusLyrics(String html) {
  const marker = 'data-lyrics-container="true"';
  final parts = <String>[];
  var from = 0;

  while (true) {
    final at = html.indexOf(marker, from);
    if (at < 0) break;
    final open = html.indexOf('>', at);
    if (open < 0) break;

    // Ищем закрывающий </div> с учётом вложенных div.
    var depth = 1;
    var i = open + 1;
    final tag = RegExp(r'<(/?)div\b', caseSensitive: false);
    var end = -1;
    for (final m in tag.allMatches(html, i)) {
      depth += m.group(1) == '/' ? -1 : 1;
      if (depth == 0) {
        end = m.start;
        break;
      }
    }
    if (end < 0) break;
    parts.add(html.substring(open + 1, end));
    from = end;
  }

  if (parts.isEmpty) return null;
  final text = htmlToText(parts.join('\n'));
  return text.isEmpty ? null : text;
}

String htmlToText(String html) {
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
  return text
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Выбирает со страницы поиска Lyricsify ссылку на песню
/// (`/lyric/...` или `/lyrics/...`), подходящую по названию, иначе первую.
String? pickLyricsifyPath(
  String html, {
  required String artist,
  required String title,
}) {
  final links = RegExp(
    "href=[\"'](/lyrics?/[^\"'#?\\s]+)[\"']",
    caseSensitive: false,
  ).allMatches(html).map((m) => m.group(1)!).toList();
  if (links.isEmpty) return null;

  final wantTitle = _norm(title);
  final wantArtist = _norm(artist.split(',').first);
  for (final path in links) {
    final slug =
        _norm(Uri.decodeComponent(path).replaceAll(RegExp(r'[-_/]'), ' '));
    if (slug.contains(wantTitle) &&
        (wantArtist.isEmpty || slug.contains(wantArtist))) {
      return path;
    }
  }
  return links.first;
}

/// Достаёт из HTML строки с таймкодами и собирает LRC. Нужно не меньше
/// трёх таких строк, иначе это не текст песни (например, защитная страница).
String? extractLrcFromHtml(String html) {
  final text = htmlToText(html);
  final lines = <String>[];
  final stamp = RegExp(r'^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (stamp.hasMatch(line)) lines.add(line);
  }
  if (lines.length < 3) return null;
  return lines.join('\n');
}
