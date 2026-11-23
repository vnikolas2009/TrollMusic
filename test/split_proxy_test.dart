import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/split_proxy.dart';

/// Минимальный ClientHello с одним расширением server_name.
Uint8List clientHello(String host) {
  final name = host.codeUnits;
  final sni = <int>[
    0, 0, // тип server_name
    ...[(name.length + 5) >> 8, (name.length + 5) & 0xff],
    ...[(name.length + 3) >> 8, (name.length + 3) & 0xff],
    0, // host_name
    ...[name.length >> 8, name.length & 0xff],
    ...name,
  ];
  final body = <int>[
    3, 3, // version
    ...List.filled(32, 7), // random
    0, // session id
    0, 2, 0x13, 0x01, // cipher suites
    1, 0, // compression
    ...[sni.length >> 8, sni.length & 0xff],
    ...sni,
  ];
  final handshake = <int>[
    1,
    0,
    body.length >> 8,
    body.length & 0xff,
    ...body,
  ];
  return Uint8List.fromList([
    0x16, 3, 1,
    handshake.length >> 8, handshake.length & 0xff,
    ...handshake,
  ]);
}

void main() {
  test('точка разреза лежит внутри имени сервера', () {
    final data = clientHello('api-v2.soundcloud.com');
    final at = findSniSplit(data)!;
    final text = String.fromCharCodes(data);
    final start = text.indexOf('api-v2.soundcloud.com');
    expect(at, greaterThan(start));
    expect(at, lessThan(start + 'api-v2.soundcloud.com'.length));
  });

  test('не-ClientHello и обрезанные данные дают null', () {
    expect(findSniSplit(Uint8List.fromList([1, 2, 3])), isNull);
    expect(findSniSplit(Uint8List(100)), isNull);
    final data = clientHello('example.com');
    expect(findSniSplit(Uint8List.sublistView(data, 0, 50)), isNull);
  });
}
