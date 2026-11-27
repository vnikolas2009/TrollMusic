import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/track_filter.dart';
import 'package:trollmusic/data/models/track.dart';

void main() {
  Track t(String? art) => Track(id: 'x', title: 'x', artist: 'a', artworkPath: art);

  test('без пути — нет обложки', () {
    expect(lacksArtwork(t(null), exists: (_) => true), isTrue);
    expect(lacksArtwork(t(''), exists: (_) => true), isTrue);
  });

  test('путь есть, файла нет — нет обложки', () {
    expect(lacksArtwork(t('/a.jpg'), exists: (_) => false), isTrue);
  });

  test('путь и файл есть — обложка есть', () {
    expect(lacksArtwork(t('/a.jpg'), exists: (_) => true), isFalse);
  });
}
