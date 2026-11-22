import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// DNS-over-HTTPS резолвер (Google 8.8.8.8, Quad9 9.9.9.9).
///
/// Сами DoH-запросы идут на IP-адреса обычным [HttpClient], поэтому
/// рекурсии через системный DNS нет. При неудаче используется системный DNS.
class DohResolver {
  DohResolver({List<String>? endpoints, HttpClient Function()? clientFactory})
      : _endpoints = endpoints ?? AppConfig.dohEndpoints,
        _clientFactory = clientFactory ?? HttpClient.new;

  static final DohResolver shared = DohResolver();

  final List<String> _endpoints;
  final HttpClient Function() _clientFactory;
  final Map<String, _Entry> _cache = {};
  final Map<String, Future<List<InternetAddress>>> _inflight = {};

  Future<List<InternetAddress>> lookup(String host) {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return Future.value([literal]);

    final hit = _cache[host];
    if (hit != null && hit.expires.isAfter(DateTime.now())) {
      return Future.value(hit.addresses);
    }
    return _inflight[host] ??= _resolve(host).whenComplete(() {
      _inflight.remove(host);
    });
  }

  Future<List<InternetAddress>> _resolve(String host) async {
    for (final endpoint in _endpoints) {
      try {
        final result = await _query(endpoint, host).timeout(AppConfig.dohTimeout);
        if (result.addresses.isNotEmpty) {
          _cache[host] = _Entry(
            result.addresses,
            DateTime.now().add(Duration(seconds: result.ttl.clamp(60, 900))),
          );
          return result.addresses;
        }
      } catch (_) {
        // Следующий DoH-сервер.
      }
    }
    return InternetAddress.lookup(host, type: InternetAddressType.IPv4);
  }

  Future<({List<InternetAddress> addresses, int ttl})> _query(
    String endpoint,
    String host,
  ) async {
    final client = _clientFactory()
      ..connectionTimeout = AppConfig.dohTimeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri.parse(endpoint).replace(
        queryParameters: {'name': host, 'type': 'A'},
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('DoH ${response.statusCode}', uri: uri);
      }
      final body = await utf8.decoder.bind(response).join();
      return parseDohResponse(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Разбор JSON-ответа DoH (`application/dns-json`). Берутся только A-записи.
  static ({List<InternetAddress> addresses, int ttl}) parseDohResponse(
    String body,
  ) {
    final json = jsonDecode(body);
    final answers = json is Map ? json['Answer'] : null;
    final out = <InternetAddress>[];
    var ttl = 300;
    if (answers is List) {
      for (final answer in answers) {
        if (answer is! Map || answer['type'] != 1) continue;
        final address = InternetAddress.tryParse('${answer['data']}');
        if (address == null) continue;
        out.add(address);
        final t = answer['TTL'];
        if (t is num) ttl = t.toInt();
      }
    }
    return (addresses: out, ttl: ttl);
  }

  /// `HttpClient.connectionFactory`: подставляет адрес из DoH, сохраняя
  /// имя хоста для TLS (SNI и проверка сертификата делает сам HttpClient).
  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    final addresses = await lookup(uri.host);
    Object? lastError;
    for (final address in addresses) {
      try {
        final task = await Socket.startConnect(address, uri.port);
        await task.socket.timeout(AppConfig.connectTimeout);
        return task;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? SocketException('DoH: нет адресов для ${uri.host}');
  }
}

class _Entry {
  _Entry(this.addresses, this.expires);

  final List<InternetAddress> addresses;
  final DateTime expires;
}
