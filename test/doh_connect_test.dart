import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/doh_resolver.dart';

void main() {
  test('connect подключается к IP-литералу и отдаёт рабочий сокет', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((client) => client.destroy());

    final task = await DohResolver().connect(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      null,
      null,
    );
    final socket = await task.socket;
    expect(socket.remotePort, server.port);
    socket.destroy();
  });

  test('connect пробует следующий адрес, если первый не отвечает', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((client) => client.destroy());

    // Порт, на котором никто не слушает, затем рабочий: имитируем
    // «мёртвый» первый адрес из DoH.
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = closed.port;
    await closed.close();

    var failedFirst = false;
    try {
      await Socket.connect(InternetAddress.loopbackIPv4, deadPort,
          timeout: const Duration(seconds: 1));
    } on SocketException {
      failedFirst = true;
    }
    expect(failedFirst, isTrue);

    final task = await DohResolver().connect(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      null,
      null,
    );
    final socket = await task.socket;
    expect(socket.remotePort, server.port);
    socket.destroy();
  });
}
