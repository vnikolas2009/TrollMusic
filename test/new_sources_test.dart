import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/audius/audius_service.dart';
import 'package:trollmusic/core/network/vk/vk_music_service.dart';
import 'package:trollmusic/core/network/yandex/yandex_music_service.dart';
import 'package:trollmusic/data/models/track.dart';

void main() {
  group('Audius', () {
    const body = '''
{"data":[
  {"id":"D7KyD","title":"Song","genre":"Electronic","duration":215,
   "is_streamable":true,
   "artwork":{"150x150":"https://a/150","480x480":"https://a/480"},
   "user":{"name":"Artist","handle":"artist"}},
  {"id":"D7KyD","title":"Duplicate","duration":1,"user":{"name":"X"}},
  {"id":"gone1","title":"Hidden","is_streamable":false,"user":{"name":"X"}},
  {"id":"nouser","title":"No user","duration":10}
]}''';

    test('разбирает треки, пропуская дубли и недоступные', () {
      final tracks = parseAudiusTracks(body);
      expect(tracks.map((t) => t.id), ['au:D7KyD', 'au:nouser']);
      final first = tracks.first;
      expect(first.title, 'Song');
      expect(first.artist, 'Artist');
      expect(first.duration, const Duration(seconds: 215));
      expect(first.thumbnailUrl, 'https://a/480');
      expect(first.source, TrackSource.audius);
      expect(tracks.last.artist, 'Audius');
    });

    test('учитывает лимит и пустые ответы', () {
      expect(parseAudiusTracks(body, limit: 1), hasLength(1));
      expect(parseAudiusTracks('{"data":[]}'), isEmpty);
      expect(parseAudiusTracks('{"nope":1}'), isEmpty);
    });

    test('rawId принимает только буквы и цифры', () {
      expect(audiusRawId('au:D7KyD'), 'D7KyD');
      expect(audiusRawId('D7KyD'), 'D7KyD');
      expect(audiusRawId('au:../x'), '');
      expect(audiusRawId('au:'), '');
      expect(
        audiusStreamUrl('D7KyD'),
        'https://api.audius.co/v1/tracks/D7KyD/stream?app_name=TrollMusic',
      );
    });
  });

  group('Яндекс Музыка', () {
    test('разбирает поиск', () {
      const body = '''
{"result":{"tracks":{"results":[
  {"id":"123","title":"Трек","version":"Remix","durationMs":185000,
   "coverUri":"avatars.yandex.net/get-music/1/abc/%%",
   "contentWarning":"explicit","available":true,
   "artists":[{"name":"А"},{"name":"Б"}],
   "albums":[{"id":77,"title":"Альбом"}]},
  {"id":123,"title":"Дубль"},
  {"id":"9","title":"Нет","available":false}
]}}}''';
      final tracks = parseYandexSearch(body);
      expect(tracks, hasLength(1));
      final t = tracks.single;
      expect(t.id, 'ym:123');
      expect(t.title, 'Трек (Remix)');
      expect(t.artist, 'А, Б');
      expect(t.album, 'Альбом');
      expect(t.albumId, '77');
      expect(t.duration, const Duration(milliseconds: 185000));
      expect(t.thumbnailUrl, 'https://avatars.yandex.net/get-music/1/abc/400x400');
      expect(t.explicit, isTrue);
      expect(t.source, TrackSource.yandex);
    });

    test('разбирает чарт с обёрткой track и без неё', () {
      const body = '''
{"result":{"chart":{"tracks":[
  {"track":{"id":"1","title":"A","artists":[{"name":"X"}]}},
  {"id":"2","title":"B","artists":[]}
]}}}''';
      final tracks = parseYandexChart(body);
      expect(tracks.map((t) => t.id), ['ym:1', 'ym:2']);
      expect(tracks.last.artist, 'Яндекс Музыка');
    });

    test('rawId допускает трек и трек:альбом', () {
      expect(yandexRawId('ym:123'), '123');
      expect(yandexRawId('ym:123:456'), '123:456');
      expect(yandexRawId('ym:abc'), '');
      expect(yandexRawId('ym:1/2'), '');
    });

    test('выбор битрейта: не выше цели, иначе минимальный', () {
      const v = <YandexVariant>[
        (bitrate: 320, url: 'u320'),
        (bitrate: 128, url: 'u128'),
        (bitrate: 192, url: 'u192'),
      ];
      expect(pickYandexVariant(v, targetBitrate: 200)!.url, 'u192');
      expect(pickYandexVariant(v, targetBitrate: 320)!.url, 'u320');
      expect(pickYandexVariant(v, targetBitrate: 64)!.url, 'u128');
      expect(pickYandexVariant(const [], targetBitrate: 128), isNull);
    });

    test('download-info оставляет только mp3', () {
      const body = '''
{"result":[
  {"codec":"aac","bitrateInKbps":64,"downloadInfoUrl":"https://x/aac"},
  {"codec":"mp3","bitrateInKbps":192,"downloadInfoUrl":"https://x/mp3"},
  {"codec":"mp3","bitrateInKbps":128}
]}''';
      final v = parseYandexDownloadInfo(body);
      expect(v, hasLength(1));
      expect(v.single.bitrate, 192);
    });

    test('format=json добавляется ровно один раз', () {
      expect(yandexJsonInfoUrl('https://x/y'), 'https://x/y?format=json');
      expect(yandexJsonInfoUrl('https://x/y?a=1'), 'https://x/y?a=1&format=json');
      expect(
        yandexJsonInfoUrl('https://x/y?format=json'),
        'https://x/y?format=json',
      );
    });

    test('прямая ссылка подписывается md5(соль + путь + s)', () {
      const body = '{"host":"s1.storage.yandex.net","path":"/abc/def.mp3",'
          '"ts":"0005","s":"sval"}';
      expect(
        yandexDirectLink(body),
        'https://s1.storage.yandex.net/get-mp3/'
        '4392d16e648b0c4329e3c8cb6a132f26/0005/abc/def.mp3',
      );
    });

    test('прямая ссылка отвергает подозрительный хост и пустые поля', () {
      expect(
        yandexDirectLink(
          '{"host":"evil.com/x","path":"/a","ts":"1","s":"2"}',
        ),
        isNull,
      );
      expect(
        yandexDirectLink('{"host":"h.net","path":"a","ts":"1","s":"2"}'),
        isNull,
      );
      expect(yandexDirectLink('{"host":"h.net","path":"/a"}'), isNull);
      expect(yandexDirectLink('[]'), isNull);
    });

    test('обложка: пустое значение и уже полный URL', () {
      expect(yandexCoverUrl(null), isNull);
      expect(yandexCoverUrl('  '), isNull);
      expect(yandexCoverUrl('https://h/%%', size: 200), 'https://h/200x200');
    });
  });

  group('VK Музыка', () {
    test('разбирает audio.search и не сохраняет url', () {
      const body = '''
{"response":{"count":2,"items":[
  {"owner_id":-5,"id":10,"title":"Т","artist":"А","duration":200,
   "is_explicit":true,"url":"https://cs.vk/x.m3u8",
   "album":{"title":"Альбом","thumb":{"photo_300":"https://p/300"}}},
  {"owner_id":-5,"id":10,"title":"Дубль"},
  {"owner_id":7,"id":8}
]}}''';
      final tracks = parseVkAudio(body);
      expect(tracks.map((t) => t.id), ['vk:-5_10', 'vk:7_8']);
      final t = tracks.first;
      expect(t.title, 'Т');
      expect(t.artist, 'А');
      expect(t.album, 'Альбом');
      expect(t.thumbnailUrl, 'https://p/300');
      expect(t.explicit, isTrue);
      expect(t.streamUrl, isNull);
      expect(t.source, TrackSource.vk);
      expect(tracks.last.artist, 'VK Музыка');
    });

    test('ошибка VK превращается в пустой список', () {
      const err = '{"error":{"error_code":15,"error_msg":"denied"}}';
      expect(parseVkAudio(err), isEmpty);
      expect(isVkError(err), isTrue);
      expect(isVkError('{"response":[]}'), isFalse);
      expect(isVkError('не json'), isFalse);
    });

    test('rawId и ссылка на поток', () {
      expect(vkRawId('vk:-5_10'), '-5_10');
      expect(vkRawId('vk:5_10'), '5_10');
      expect(vkRawId('vk:5'), '');
      expect(vkRawId('vk:a_b'), '');

      expect(
        vkStreamUrl('{"response":[{"url":"https://cs.vk/a.mp3"}]}'),
        'https://cs.vk/a.mp3',
      );
      expect(
        vkStreamUrl('{"response":[{"url":"http://cs.vk/a.mp3"}]}'),
        isNull,
      );
      expect(vkStreamUrl('{"response":[]}'), isNull);
      expect(vkStreamUrl('{"error":{}}'), isNull);
    });
  });

  test('новые источники переживают сохранение трека в JSON', () {
    for (final source in [
      TrackSource.yandex,
      TrackSource.vk,
      TrackSource.audius,
    ]) {
      final track = Track(
        id: 'x',
        title: 't',
        artist: 'a',
        source: source,
      );
      expect(Track.fromJson(track.toJson()).source, source);
    }
  });
}
