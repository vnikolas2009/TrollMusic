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

/// Делит одну TLS-запись ClientHello на две в позиции [at] (абсолютный
/// индекс внутри [data], не раньше конца заголовка записи).
///
/// Это аналог `tlsrec` из zapret: сервер по стандарту собирает
/// фрагментированные записи обратно, а фильтры, ищущие имя сайта в одной
/// записи, его не находят. Возвращает `null`, если пакет не подходит.
Uint8List? fragmentTlsRecord(Uint8List data, int at) {
  if (data.length < 6 || data[0] != 0x16) return null;
  final length = (data[3] << 8) | data[4];
  final end = 5 + length;
  if (at <= 5 || at >= end || end > data.length) return null;

  final firstLen = at - 5;
  final secondLen = length - firstLen;
  final out = BytesBuilder(copy: false)
    ..add([data[0], data[1], data[2], firstLen >> 8, firstLen & 0xff])
    ..add(Uint8List.sublistView(data, 5, at))
    ..add([data[0], data[1], data[2], secondLen >> 8, secondLen & 0xff])
    ..add(Uint8List.sublistView(data, at));
  return out.toBytes();
}

/// Способы отправить первый пакет рукопожатия. Если провайдер режет
/// соединение при одном способе, пробуется следующий.
enum BypassStrategy {
  /// Обычный пакет, разрезанный на два TCP-сегмента внутри имени сервера.
  tcpSplit,

  /// Две TLS-записи, граница между ними внутри имени, два TCP-сегмента.
  tlsRecordSplit,

  /// Две TLS-записи в одном TCP-сегменте.
  tlsRecord,

  /// Первый байт отдельным сегментом, затем две TLS-записи.
  earlySplit,
}

/// Части, в которых нужно отправить [hello] выбранным способом. Если
/// способ не применим к пакету, возвращает его целиком.
List<Uint8List> planClientHello(Uint8List hello, BypassStrategy strategy) {
  final at = findSniSplit(hello);
  if (at == null) return [hello];

  switch (strategy) {
    case BypassStrategy.tcpSplit:
      return [
        Uint8List.sublistView(hello, 0, at),
        Uint8List.sublistView(hello, at),
      ];
    case BypassStrategy.tlsRecordSplit:
      final f = fragmentTlsRecord(hello, at);
      if (f == null) return [hello];
      return [
        Uint8List.sublistView(f, 0, at),
        Uint8List.sublistView(f, at),
      ];
    case BypassStrategy.tlsRecord:
      return [fragmentTlsRecord(hello, at) ?? hello];
    case BypassStrategy.earlySplit:
      final f = fragmentTlsRecord(hello, at) ?? hello;
      return [
        Uint8List.sublistView(f, 0, 1),
        Uint8List.sublistView(f, 1),
      ];
  }
}

/// Порядок способов, начиная с запомненного для узла.
List<BypassStrategy> strategyOrder(BypassStrategy? remembered) {
  const all = BypassStrategy.values;
  if (remembered == null) return all;
  return [remembered, ...all.where((s) => s != remembered)];
}

/// Локальный HTTP-прокси (только `CONNECT`) для обхода блокировок по SNI.
///
/// Приложение ходит через него по HTTPS: прокси подключается к серверу
/// (адрес берётся через DoH) и первый пакет рукопожатия отправляет
/// несколькими способами (см. [BypassStrategy]) до первого ответа сервера.
/// Удачный способ запоминается для узла. Дальше трафик идёт как есть,
/// шифрование остаётся сквозным: прокси ничего не расшифровывает.
///
/// Ограничение: приёмы zapret с поддельными пакетами (fake, TTL, md5sig,
/// disorder) требуют перехвата пакетов на уровне системы и без root
/// в мобильном приложении невозможны.
class SplitProxy {
  SplitProxy._();

  static final SplitProxy shared = SplitProxy._();

  /// Сколько ждать ответа сервера после первого пакета.
  static const _replyTimeout = Duration(seconds: 4);

  ServerSocket? _server;
  final Map<String, BypassStrategy> _remembered = {};

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
    String? host;
    var port = 443;
    var tunnelled = false;
    var opening = false;
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
            if (host == null) {
              buffer.add(chunk);
              final head = String.fromCharCodes(buffer.toBytes());
              if (!head.contains('\r\n\r\n')) return;

              final first = head.split('\r\n').first.split(' ');
              if (first.length < 2 || first[0].toUpperCase() != 'CONNECT') {
                client.write('HTTP/1.1 405 Method Not Allowed\r\n\r\n');
                closeAll();
                return;
              }
              final target = first[1];
              final colon = target.lastIndexOf(':');
              host = colon < 0 ? target : target.substring(0, colon);
              port = colon < 0 ? 443 : int.parse(target.substring(colon + 1));

              // Соединение с сервером откроем после первого пакета клиента:
              // его нужно будет отправить заново, если способ не сработает.
              client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
              await client.flush();
              return;
            }

            if (opening) return;
            opening = true;
            sub!.pause();
            final hello = Uint8List.fromList(chunk);
            final connection = await _open(host!, port, hello);
            if (connection == null) {
              closeAll();
              return;
            }
            upstream = connection.socket;
            tunnelled = true;
            if (connection.first.isNotEmpty) client.add(connection.first);
            unawaited(_pump(connection.iterator, client, closeAll));
            sub!.resume();
            return;
          }

          upstream!.add(chunk);
        } catch (_) {
          closeAll();
        }
      },
      onDone: closeAll,
      onError: (_) => closeAll(),
      cancelOnError: true,
    );
  }

  Future<void> _pump(
    StreamIterator<Uint8List> iterator,
    Socket client,
    void Function() closeAll,
  ) async {
    try {
      while (await iterator.moveNext()) {
        client.add(iterator.current);
      }
    } catch (_) {}
    closeAll();
  }

  /// Открывает соединение и отправляет [hello]. Для TLS перебирает способы
  /// и возвращает первое соединение, где сервер ответил.
  Future<_Opened?> _open(String host, int port, Uint8List hello) async {
    if (findSniSplit(hello) == null) {
      // Не TLS или без SNI: отправляем как есть.
      final socket = await _connect(host, port);
      if (socket == null) return null;
      final it = StreamIterator<Uint8List>(socket);
      socket.add(hello);
      return _Opened(socket, it, Uint8List(0));
    }

    for (final strategy in strategyOrder(_remembered[host])) {
      final socket = await _connect(host, port);
      if (socket == null) return null;
      final it = StreamIterator<Uint8List>(socket);
      try {
        final parts = planClientHello(hello, strategy);
        for (var i = 0; i < parts.length; i++) {
          socket.add(parts[i]);
          if (i < parts.length - 1) {
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
        }
        final got = await it.moveNext().timeout(_replyTimeout);
        if (got) {
          _remembered[host] = strategy;
          return _Opened(socket, it, Uint8List.fromList(it.current));
        }
      } catch (_) {}
      socket.destroy();
    }
    return null;
  }

  Future<Socket?> _connect(String host, int port) async {
    try {
      final socket = await DohResolver.shared.connectHost(host, port);
      socket.setOption(SocketOption.tcpNoDelay, true);
      return socket;
    } catch (_) {
      return null;
    }
  }
}

class _Opened {
  _Opened(this.socket, this.iterator, this.first);

  final Socket socket;
  final StreamIterator<Uint8List> iterator;
  final Uint8List first;
}
