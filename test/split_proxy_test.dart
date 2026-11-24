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
  splitProxyStrategyTests();

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

void splitProxyStrategyTests() {
  group('обход: способы отправки ClientHello', () {
    final hello = clientHello('api-v2.soundcloud.com');
    final at = findSniSplit(hello)!;

    Uint8List join(List<Uint8List> parts) =>
        Uint8List.fromList([for (final p in parts) ...p]);

    test('fragmentTlsRecord: две записи с исходным содержимым', () {
      final f = fragmentTlsRecord(hello, at)!;
      expect(f.length, hello.length + 5);
      final len1 = (f[3] << 8) | f[4];
      expect(len1, at - 5);
      expect(f[5 + len1], 0x16);
      final len2 = (f[5 + len1 + 3] << 8) | f[5 + len1 + 4];
      expect(len1 + len2, hello.length - 5);
      final payload = [
        ...f.sublist(5, 5 + len1),
        ...f.sublist(5 + len1 + 5),
      ];
      expect(payload, hello.sublist(5));
    });

    test('fragmentTlsRecord: плохая позиция даёт null', () {
      expect(fragmentTlsRecord(hello, 3), isNull);
      expect(fragmentTlsRecord(hello, hello.length), isNull);
      expect(fragmentTlsRecord(Uint8List.fromList([1, 2, 3, 4, 5, 6]), 5),
          isNull);
    });

    test('tcpSplit: части склеиваются в исходный пакет', () {
      final parts = planClientHello(hello, BypassStrategy.tcpSplit);
      expect(parts.length, 2);
      expect(join(parts), hello);
    });

    test('tlsRecordSplit и earlySplit: части дают фрагментированный пакет', () {
      final f = fragmentTlsRecord(hello, at)!;
      final a = planClientHello(hello, BypassStrategy.tlsRecordSplit);
      expect(a.length, 2);
      expect(join(a), f);
      final b = planClientHello(hello, BypassStrategy.earlySplit);
      expect(b.first.length, 1);
      expect(join(b), f);
    });

    test('tlsRecord: один сегмент', () {
      final parts = planClientHello(hello, BypassStrategy.tlsRecord);
      expect(parts.length, 1);
      expect(parts.first, fragmentTlsRecord(hello, at));
    });

    test('не TLS: пакет не меняется', () {
      final plain = Uint8List.fromList('GET / HTTP/1.1\r\n\r\n'.codeUnits);
      for (final s in BypassStrategy.values) {
        expect(planClientHello(plain, s), [plain]);
      }
    });

    test('strategyOrder: запомненный первым, без повторов', () {
      expect(strategyOrder(null), BypassStrategy.values);
      final order = strategyOrder(BypassStrategy.tlsRecord);
      expect(order.first, BypassStrategy.tlsRecord);
      expect(order.toSet().length, BypassStrategy.values.length);
    });
  });
}
