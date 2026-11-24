import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/path_repair.dart';

void main() {
  test('файл на месте: путь не меняется', () {
    expect(
      repairedPath('/a/trollmusic/audio/x.m4a', '/b/trollmusic',
          exists: (_) => true),
      isNull,
    );
  });

  test('старый контейнер iOS: ищем файл в новой папке', () {
    final r = repairedPath(
      '/old/UUID1/trollmusic/audio/x.m4a',
      '/new/UUID2/trollmusic',
      exists: (path) => path == '/new/UUID2/trollmusic/audio/x.m4a',
    );
    expect(r, '/new/UUID2/trollmusic/audio/x.m4a');
  });

  test('файла нет нигде: null', () {
    expect(
      repairedPath('/old/audio/x.m4a', '/new', exists: (_) => false),
      isNull,
    );
  });

  test('пустой путь', () {
    expect(repairedPath('', '/new'), isNull);
    expect(repairedPath(null, '/new'), isNull);
  });

  test('safeFileName', () {
    expect(safeFileName('sc:123'), 'sc_123');
    expect(safeFileName('a/b c'), 'a_b_c');
  });
}
