import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'doh_resolver.dart';

/// Позиция внутри имени сервера (SNI) в первом TLS-пакете ClientHello
/// или `null`, если пакет не похож на ClientHello.
///
/// Фильтры по SNI часто ищут имя сайта целиком в первом TCP-сегменте.
/// Если разрезать пакет посередине имени, такой фильтр его не видит, а
/// настоящий сервер собирает пакет обратно и отвечает как обычно.
int? findSniSplit(Uint8List data) {
  try {
    // TLS record: 0x16 handshake, ClientHello = 0x01.
    if (data.length < 45 || data[0] != 0x16 || data[5] != 0x01) return null;

    var i = 43; // после version(2) + random(32) в handshake
    i += 1 + data[i]; // session id
    if (i + 2 > data.length) return null;
    i += 2 + ((data[i] << 8) | data[i + 1]); // cipher suites
    if (i + 1 > data.length) return null;
    i += 1 + data[i]; // compression methods
    if (i + 2 > data.length) return null;

    final extEnd = i + 2 + ((data[i] << 8) | data[i + 1]);
    i += 2;

    while (i + 4 <= extEnd && i + 4 <= data.length) {
      final type = (data[i] << 8) | data[i + 1];
      final len = (data[i + 2] << 8) | data[i + 3];
      i += 4;
      if (type == 0x0000) {
        // server_name: list len(2), name type(1), name len(2), name
        if (i + 5 > data.length) return null;
        final nameLen = (data[i + 3] << 8) | data[i + 4];
        final nameStart = i + 5;
        if (nameLen < 2 || nameStart + nameLen > data.length) return null;
        return nameStart + nameLen ~/ 2;
      }
      i += len;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Локальный HTTP-прокси (только `CONNECT`) для обхода блокировок по SNI.
///
/// Приложение ходит через него по HTTPS: прокси подключается к серверу
/// (адрес берётся через DoH) и первый пакет рукопожатия отправляет двумя
/// частями. Дальше трафик идёт как есть, шифрование остаётся сквозным:
/// прокси ничего не расшифровывает.
class SplitProxy {
  SplitProxy._();

  static final SplitProxy shared = SplitProxy._();

  ServerSocket? _server;

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_handle, onError: (_) {});
    } catch (_) {
      _server = null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  Future<void> _handle(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);
    Socket? upstream;
    final buffer = BytesBuilder();
    var tunnelled = false;
    var firstPacketSent = false;
    StreamSubscription<Uint8List>? sub;

    void closeAll() {
      sub?.cancel();
      client.destroy();
      upstream?.destroy();
    }

    sub = client.listen(
      (chunk) async {
        try {
          if (!tunnelled) {
            buffer.add(chunk);
            final head = String.fromCharCodes(buffer.toBytes());
            final end = head.indexOf('\r\n\r\n');
            if (end < 0) return;

            final first = head.split('\r\n').first.split(' ');
            if (first.length < 2 || first[0].toUpperCase() != 'CONNECT') {
              client.write('HTTP/1.1 405 Method Not Allowed\r\n\r\n');
              closeAll();
              return;
            }

            sub!.pause();
            final target = first[1];
            final colon = target.lastIndexOf(':');
            final host = colon < 0 ? target : target.substring(0, colon);
            final port = colon < 0 ? 443 : int.parse(target.substring(colon + 1));

            final socket = await DohResolver.shared.connectHost(host, port);
            socket.setOption(SocketOption.tcpNoDelay, true);
            upstream = socket;
            tunnelled = true;

            socket.listen(
              client.add,
              onDone: closeAll,
              onError: (_) => closeAll(),
              cancelOnError: true,
            );

            client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            await client.flush();
            sub!.resume();
            return;
          }

          final out = upstream!;
          if (!firstPacketSent) {
            firstPacketSent = true;
            final bytes = Uint8List.fromList(chunk);
            final at = findSniSplit(bytes);
            if (at != null) {
              out.add(Uint8List.sublistView(bytes, 0, at));
              await out.flush();
              await Future<void>.delayed(const Duration(milliseconds: 15));
              out.add(Uint8List.sublistView(bytes, at));
              return;
            }
          }
          out.add(chunk);
        } catch (_) {
          closeAll();
        }
      },
      onDone: closeAll,
      onError: (_) => closeAll(),
      cancelOnError: true,
    );
  }
}
