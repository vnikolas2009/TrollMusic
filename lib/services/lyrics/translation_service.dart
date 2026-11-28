import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/network/http_client.dart';
import '../../core/utils/translation.dart';

/// Перевод строк текста: [lines] выровнены по [translationSourceLines]
/// (для пустых строк — пустая строка).
class TranslationResult {
  const TranslationResult({required this.lines, required this.lang, this.sourceLang});

  final List<String> lines;
  final String lang;
  final String? sourceLang;

  /// Текст уже на выбранном языке: показывать перевод незачем.
  bool get isSameLanguage => sameLanguage(sourceLang, lang);
}

class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Перевод текстов песен через бесплатную конечную точку Google Translate
/// (без ключа; неофициальная, как Kugou и QQ для текстов). Готовый перевод
/// кэшируется в `<root>/translations`, повторно сеть не нужна.
class TranslationService {
  TranslationService({required this.root, Dio? dio})
      : _dio = dio ?? createDio(receiveTimeout: const Duration(seconds: 25));

  final Directory root;
  final Dio _dio;

  /// Основной и запасной адреса; запасной пробуется при сбое первого.
  static const _endpoints = [
    'https://translate.googleapis.com/translate_a/single',
    'https://translate.google.com/translate_a/single',
  ];

  Directory get _dir => Directory(p.join(root.path, 'translations'));

  File _cacheFile(String trackId, String lang) {
    final safe = trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(_dir.path, '${safe}_$lang.json'));
  }

  /// Перевод из кэша, если он есть и текст песни не менялся.
  Future<TranslationResult?> cached(String trackId, String lang, List<String> source) async {
    try {
      final file = _cacheFile(trackId, lang);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['hash'] != linesHash(source)) return null;
      final lines = (json['lines'] as List).cast<String>();
      if (lines.length != source.length) return null;
      return TranslationResult(
        lines: lines,
        lang: lang,
        sourceLang: json['sourceLang'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<TranslationResult> translate(String trackId, List<String> source, String lang) async {
    final hit = await cached(trackId, lang, source);
    if (hit != null) return hit;

    final out = List<String>.filled(source.length, '');
    String? sourceLang;

    for (final chunk in chunkIndices(source)) {
      final texts = [for (final i in chunk) source[i].trim()];
      final part = await _translateChunk(texts, lang);
      sourceLang ??= part.sourceLang;
      for (var k = 0; k < chunk.length; k++) {
        out[chunk[k]] = part.rows[k];
      }
    }

    final result = TranslationResult(lines: out, lang: lang, sourceLang: sourceLang);
    await _save(trackId, lang, source, result);
    return result;
  }

  /// Какой провайдер сработал последним: со следующего пакета (и перевода)
  /// начинаем с него, чтобы не ждать таймаут заблокированного.
  bool _microsoftFirst = false;

  /// Перевод пакета строк: Google (два адреса), при сбое — Microsoft Edge
  /// Translator. Часть сетей и VPN режет один из сервисов, второй обычно
  /// доступен.
  Future<({List<String> rows, String? sourceLang})> _translateChunk(
    List<String> texts,
    String lang,
  ) async {
    final order = _microsoftFirst ? [true, false] : [false, true];
    final failures = <String>[];
    for (final microsoft in order) {
      try {
        final result = microsoft
            ? await _translateMicrosoft(texts, lang)
            : await _translateGoogle(texts, lang);
        _microsoftFirst = microsoft;
        return result;
      } on TranslationException catch (e) {
        failures.add('${microsoft ? 'Microsoft' : 'Google'}: ${e.message}');
      }
    }
    // Показываем причины обоих сервисов, чтобы было понятно, что не так.
    throw TranslationException(failures.join('\n'));
  }

  Future<({List<String> rows, String? sourceLang})> _translateGoogle(
    List<String> texts,
    String lang,
  ) async {
    final joined = await _request(texts.join('\n'), lang);
    var rows = splitTranslated(joined.text, texts.length);
    if (rows == null) {
      // Строки склеились или разъехались: переводим по одной.
      rows = [];
      for (final text in texts) {
        rows.add((await _request(text, lang)).text.replaceAll('\n', ' ').trim());
      }
    }
    return (rows: rows, sourceLang: joined.sourceLang);
  }

  String? _msToken;
  DateTime _msTokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String> _microsoftToken() async {
    if (_msToken != null && DateTime.now().difference(_msTokenAt) < const Duration(minutes: 8)) {
      return _msToken!;
    }
    final response = await _dio.get<String>(
      'https://edge.microsoft.com/translate/auth',
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 5,
        headers: _edgeHeaders,
      ),
    );
    final token = response.data?.trim();
    if (response.statusCode != 200 || token == null || token.isEmpty) {
      throw TranslationException('не выдал доступ (код ${response.statusCode})');
    }
    _msToken = token;
    _msTokenAt = DateTime.now();
    return token;
  }

  static const _edgeHeaders = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Safari/537.36 Edg/124.0',
    'accept': '*/*',
  };

  /// Код языка для Microsoft: китайский там `zh-Hans`.
  static String _microsoftLang(String code) => code == 'zh-CN' ? 'zh-Hans' : code;

  Future<({List<String> rows, String? sourceLang})> _translateMicrosoft(
    List<String> texts,
    String lang,
  ) async {
    try {
      final token = await _microsoftToken();
      final response = await _dio.post<String>(
        'https://api-edge.cognitive.microsofttranslator.com/translate',
        queryParameters: {'api-version': '3.0', 'to': _microsoftLang(lang)},
        data: jsonEncode([for (final t in texts) {'Text': t}]),
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.plain,
          headers: {..._edgeHeaders, 'authorization': 'Bearer $token'},
        ),
      );
      final code = response.statusCode ?? 0;
      if (code == 401 || code == 403) _msToken = null;
      if (code < 200 || code >= 300) {
        throw TranslationException('ответил кодом $code');
      }
      final parsed = parseMicrosoftResponse(jsonDecode(response.data ?? ''), texts.length);
      if (parsed == null) {
        throw const TranslationException('не удалось разобрать ответ');
      }
      return parsed;
    } on DioException {
      throw const TranslationException('нет связи');
    } on FormatException {
      throw const TranslationException('не удалось разобрать ответ');
    }
  }

  Future<({String text, String? sourceLang})> _request(String text, String lang) async {
    TranslationException? failure;
    for (final endpoint in _endpoints) {
      try {
        final response = await _dio.post<Object?>(
          endpoint,
          queryParameters: {'client': 'gtx', 'sl': 'auto', 'tl': lang, 'dt': 't'},
          data: {'q': text},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            // Ответ разбираем сами: тип содержимого бывает не JSON, и тогда
            // Dio отдаёт строку.
            responseType: ResponseType.plain,
            headers: const {
              'user-agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
                      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
              'accept': '*/*',
            },
          ),
        );
        final code = response.statusCode ?? 0;
        if (code == 429) {
          failure = const TranslationException('просит подождать, попробуйте позже');
          continue;
        }
        if (code >= 300 && code < 400) {
          // Обычно страница капчи или согласия: бывает у адресов VPN.
          failure = TranslationException('перенаправил запрос (код $code), возможно из-за VPN');
          continue;
        }
        if (code < 200 || code >= 300) {
          failure = TranslationException('ответил кодом $code');
          continue;
        }

        final data = response.data;
        Object? decoded;
        try {
          decoded = data is String ? jsonDecode(data) : data;
        } catch (_) {
          decoded = null;
        }
        final parsed = parseTranslateResponse(decoded);
        if (parsed == null) {
          failure = const TranslationException('не удалось разобрать ответ');
          continue;
        }
        return parsed;
      } on DioException {
        failure = const TranslationException('нет связи');
      }
    }
    throw failure ?? const TranslationException('нет связи');
  }

  Future<void> _save(String trackId, String lang, List<String> source, TranslationResult r) async {
    try {
      await _dir.create(recursive: true);
      await _cacheFile(trackId, lang).writeAsString(jsonEncode({
        'hash': linesHash(source),
        'sourceLang': r.sourceLang,
        'lines': r.lines,
      }));
    } catch (_) {
      // Кэш необязателен: перевод всё равно показывается.
    }
  }

  /// Удаляет весь кэш переводов; возвращает число удалённых файлов.
  Future<int> clearCache() async {
    var count = 0;
    try {
      if (!await _dir.exists()) return 0;
      await for (final e in _dir.list()) {
        if (e is File) {
          await e.delete();
          count++;
        }
      }
    } catch (_) {}
    return count;
  }
}
