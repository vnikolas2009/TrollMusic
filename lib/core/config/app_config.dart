abstract final class AppConfig {
  static const appName = 'TrollMusic';
  static const appVersion = '3.0.0';

  static const connectTimeout = Duration(seconds: 10);
  static const requestTimeout = Duration(seconds: 20);

  static const coverCacheWidth = 600;
  static const thumbCacheWidth = 160;

  /// Расширения аудиофайлов, которые умеет импортировать приложение.
  static const audioExtensions = <String>[
    'mp3',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'opus',
    'aac',
    'wma',
    'alac',
    'aiff',
  ];

  /// Расширения файлов с текстами песен.
  static const lyricsExtensions = <String>['lrc', 'elrc', 'txt'];

  static const userAgent =
      'TrollMusic/3.0 (+https://github.com/vnikolas2009/TrollMusic)';
}
