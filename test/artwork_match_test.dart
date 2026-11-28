import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/artwork_match.dart';

ArtworkCandidate c(String title, String artist, [String url = 'u']) =>
    ArtworkCandidate(title: title, artist: artist, url: url);

void main() {
  test('слова без регистра, скобок и знаков', () {
    expect(artworkTokens('Song (feat. Y) - Remastered!'), ['song', 'remastered']);
    expect(artworkTokens('Привет, Мир'), ['привет', 'мир']);
    expect(artworkTokens('  '), isEmpty);
  });

  test('выбирает совпадение по названию и исполнителю', () {
    final best = pickBestArtwork(
      [c('Other', 'X', 'a'), c('Song', 'Wrong', 'b'), c('Song (Remix)', 'Artist', 'c')],
      title: 'Song',
      artist: 'Artist',
    );
    expect(best?.url, 'c');
  });

  test('чужое не берёт: лучше без обложки', () {
    expect(
      pickBestArtwork([c('Different', 'Artist')], title: 'Song', artist: 'Artist'),
      isNull,
    );
    expect(pickBestArtwork(const [], title: 'Song', artist: 'Artist'), isNull);
    expect(pickBestArtwork([c('Song', 'A')], title: '', artist: 'A'), isNull);
  });

  test('неизвестный исполнитель не мешает', () {
    final best = pickBestArtwork(
      [c('Song', 'Anyone', 'z')],
      title: 'Song',
      artist: 'Неизвестный исполнитель',
    );
    expect(best?.url, 'z');
  });

  test('пустой адрес пропускается, при равенстве берётся первый', () {
    final best = pickBestArtwork(
      [c('Song', 'A', ''), c('Song', 'A', 'first'), c('Song', 'A', 'second')],
      title: 'Song',
      artist: 'A',
    );
    expect(best?.url, 'first');
  });
}
