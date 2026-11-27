import 'package:path/path.dart' as p;

import '../config/app_config.dart';

/// Поисковик для запросов из адресной строки встроенного браузера.
const browserSearchUrl = 'https://duckduckgo.com/?q=';

/// Адрес для загрузки по тексту из адресной строки: готовая ссылка остаётся
/// ссылкой, «сайт.домен» получает https, всё остальное уходит в поиск.
Uri browserTarget(String input) {
  final text = input.trim();
  if (text.isEmpty) return Uri.parse(browserSearchUrl);

  final direct = Uri.tryParse(text);
  if (direct != null && (direct.scheme == 'http' || direct.scheme == 'https') && direct.host.isNotEmpty) {
    return direct;
  }
  if (!text.contains(' ') && text.contains('.') && !text.endsWith('.')) {
    final guessed = Uri.tryParse('https://$text');
    if (guessed != null && guessed.host.contains('.')) return guessed;
  }
  return Uri.parse('$browserSearchUrl${Uri.encodeQueryComponent(text)}');
}

/// Указывает ли адрес прямо на аудиофайл (по расширению в пути).
bool looksLikeAudioUrl(Uri url) {
  if (url.scheme != 'http' && url.scheme != 'https') return false;
  final ext = p.extension(url.path).replaceFirst('.', '').toLowerCase();
  return AppConfig.audioExtensions.contains(ext);
}

const _mimeToExt = <String, String>{
  'audio/mpeg': 'mp3',
  'audio/mp3': 'mp3',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac': 'aac',
  'audio/flac': 'flac',
  'audio/x-flac': 'flac',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/ogg': 'ogg',
  'audio/opus': 'opus',
};

/// Расширение по заголовку `Content-Type`; `null`, если тип не аудио.
String? audioExtensionFromContentType(String? contentType) {
  if (contentType == null) return null;
  final mime = contentType.split(';').first.trim().toLowerCase();
  final known = _mimeToExt[mime];
  if (known != null) return known;
  return mime.startsWith('audio/') ? 'mp3' : null;
}

/// Годится ли ответ сервера: аудио либо «безымянный» бинарный поток.
bool isDownloadableAudio(String? contentType) {
  if (contentType == null) return false;
  final mime = contentType.split(';').first.trim().toLowerCase();
  return mime.startsWith('audio/') || mime == 'application/octet-stream';
}

final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1f]');

/// Имя файла для скачанного трека: из `Content-Disposition`, затем из пути
/// ссылки, затем из заголовка страницы. Расширение всегда аудио.
String downloadFileName({
  required Uri url,
  String? contentDisposition,
  String? contentType,
  String? pageTitle,
}) {
  String? name;

  if (contentDisposition != null) {
    final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false)
        .firstMatch(contentDisposition);
    final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
        .firstMatch(contentDisposition);
    final raw = star?.group(1) ?? plain?.group(1);
    if (raw != null) {
      try {
        name = Uri.decodeComponent(raw.trim());
      } catch (_) {
        name = raw.trim();
      }
    }
  }

  if (name == null || name.isEmpty) {
    final segment = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    if (segment.isNotEmpty) name = segment;
  }
  if ((name == null || name.isEmpty) && pageTitle != null) name = pageTitle;
  name = (name == null || name.trim().isEmpty) ? 'track' : name.trim();

  var ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  var base = name;
  if (AppConfig.audioExtensions.contains(ext)) {
    base = name.substring(0, name.length - ext.length - 1);
  } else {
    ext = audioExtensionFromContentType(contentType) ?? 'mp3';
  }

  base = base.replaceAll(_illegal, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (base.isEmpty) base = 'track';
  if (base.length > 120) base = base.substring(0, 120).trim();
  return '$base.$ext';
}
