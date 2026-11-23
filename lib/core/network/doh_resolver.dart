import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// DNS-over-HTTPS resolver.
///
/// Поддерживает:
/// - Google Public DNS JSON API;
/// - Cloudflare DNS JSON API;
/// - A и AAAA записи;
/// - кэширование;
/// - параллельные запросы;
/// - резервный системный DNS.
class DohResolver {
  DohResolver({
    List<String>? endpoints,
    HttpClient Function()? clientFactory,
  })  : _endpoints = endpoints ?? AppConfig.dohEndpoints,
        _clientFactory = clientFactory ?? HttpClient.new;

  static final DohResolver shared = DohResolver();

  final List<String> _endpoints;
  final HttpClient Function() _clientFactory;

  final Map<String, _Entry> _cache = {};

  final Map<String, Future<List<InternetAddress>>> _inflight = {};

  Future<List<InternetAddress>> lookup(String host) {
    final normalized = host.trim().toLowerCase();

    if (normalized.isEmpty) {
      return Future.error(
        ArgumentError.value(host, 'host', 'Empty hostname'),
      );
    }

    final literal = InternetAddress.tryParse(normalized);

    if (literal != null) {
      return Future.value([literal]);
    }

    final cached = _cache[normalized];

    if (cached != null &&
        cached.expires.isAfter(DateTime.now())) {
      return Future.value(cached.addresses);
    }

    final existing = _inflight[normalized];

    if (existing != null) {
      return existing;
    }

    final future = _resolve(normalized);

    _inflight[normalized] = future;

    return future.whenComplete(() {
      _inflight.remove(normalized);
    });
  }

  Future<List<InternetAddress>> _resolve(String host) async {
    final addresses = <InternetAddress>[];
    var minTtl = 900;

    // Все DoH-серверы опрашиваются одновременно, берём первый непустой
    // ответ. A и AAAA независимы: если AAAA не пришёл, A всё равно годится.
    // Раньше серверы шли по очереди, и при заблокированном DoH запрос
    // ждал 2 × 5 с до системного DNS.
    final answers = await Future.wait([
      for (final endpoint in _endpoints)
        _resolveVia(endpoint, host).timeout(
          AppConfig.dohTimeout,
          onTimeout: () => (addresses: <InternetAddress>[], ttl: 300),
        ),
    ]);

    for (final answer in answers) {
      if (answer.addresses.isEmpty) continue;
      addresses.addAll(answer.addresses);
      if (answer.ttl < minTtl) minTtl = answer.ttl;
    }

    final unique = <String, InternetAddress>{};
    for (final address in addresses) {
      unique[address.address] = address;
    }

    if (unique.isNotEmpty) {
      final result = _ipv4First(unique.values);
      _cache[host] = _Entry(
        result,
        DateTime.now().add(Duration(seconds: minTtl.clamp(60, 900))),
      );
      return result;
    }

    // DoH недоступен (например, заблокирован) — системный DNS.
    return _ipv4First(await InternetAddress.lookup(host));
  }

  Future<({List<InternetAddress> addresses, int ttl})> _resolveVia(
    String endpoint,
    String host,
  ) async {
    final parts = await Future.wait([
      _safeQuery(endpoint, host, 'A'),
      _safeQuery(endpoint, host, 'AAAA'),
    ]);
    final all = [for (final part in parts) ...part.addresses];
    var ttl = 900;
    for (final part in parts) {
      if (part.addresses.isNotEmpty && part.ttl < ttl) ttl = part.ttl;
    }
    return (addresses: all, ttl: ttl);
  }

  Future<({List<InternetAddress> addresses, int ttl})> _safeQuery(
    String endpoint,
    String host,
    String type,
  ) async {
    try {
      return await _query(endpoint, host, type);
    } catch (_) {
      return (addresses: <InternetAddress>[], ttl: 300);
    }
  }

  /// IPv4 первым: у многих сетей и VPN IPv6 «подвешивает» соединение.
  static List<InternetAddress> _ipv4First(Iterable<InternetAddress> list) {
    final v4 = list.where((a) => a.type == InternetAddressType.IPv4);
    final rest = list.where((a) => a.type != InternetAddressType.IPv4);
    return [...v4, ...rest];
  }

  Future<({List<InternetAddress> addresses, int ttl})> _query(
    String endpoint,
    String host,
    String type,
  ) async {
    final client = _clientFactory()
      ..connectionTimeout = AppConfig.dohTimeout
      ..findProxy = (_) => 'DIRECT';

    try {
      final uri = Uri.parse(endpoint).replace(
        queryParameters: {
          'name': host,
          'type': type,
        },
      );

      final request = await client.getUrl(uri);

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/dns-json',
      );

      request.headers.set(
        HttpHeaders.userAgentHeader,
        'TrollMusic/2.0',
      );

      final response = await request.close().timeout(
        AppConfig.dohTimeout,
      );

      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();

        throw HttpException(
          'DoH HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(AppConfig.dohTimeout);

      return parseDohResponse(body, type: type);
    } finally {
      client.close(force: true);
    }
  }

  /// Разбирает JSON-ответ Google или Cloudflare.
  ///
  /// type = A или AAAA.
  static ({
    List<InternetAddress> addresses,
    int ttl,
  }) parseDohResponse(
    String body, {
    String type = 'A',
  }) {
    final decoded = jsonDecode(body);

    if (decoded is! Map) {
      return (
        addresses: <InternetAddress>[],
        ttl: 300,
      );
    }

    final status = decoded['Status'];

    if (status is num && status.toInt() != 0) {
      return (
        addresses: <InternetAddress>[],
        ttl: 300,
      );
    }

    final expectedType = type.toUpperCase() == 'AAAA' ? 28 : 1;

    final answers = decoded['Answer'];

    final addresses = <InternetAddress>[];

    var ttl = 300;

    if (answers is List) {
      for (final answer in answers) {
        if (answer is! Map) continue;

        if (answer['type'] != expectedType) continue;

        final rawAddress = answer['data'];

        if (rawAddress is! String) continue;

        final address = InternetAddress.tryParse(rawAddress);

        if (address == null) continue;

        final correctType = expectedType == 1
            ? address.type == InternetAddressType.IPv4
            : address.type == InternetAddressType.IPv6;

        if (!correctType) continue;

        addresses.add(address);

        final rawTtl = answer['TTL'];

        if (rawTtl is num) {
          ttl = ttl < rawTtl.toInt()
              ? ttl
              : rawTtl.toInt();
        }
      }
    }

    return (
      addresses: addresses,
      ttl: ttl,
    );
  }

  /// Подключение по IP, сохраняя исходный Uri.
  ///
  /// TLS/SNI продолжает использовать исходное доменное имя.
  ///
  /// Адреса перебираются по-настоящему: каждый ждёт установки соединения
  /// ([perAddressTimeout]), и при неудаче берётся следующий. Если не ответил
  /// ни один адрес из DoH (устаревший или подменённый ответ), пробуем адреса
  /// системного DNS. Раньше `startConnect` возвращал задачу сразу, ошибка
  /// всплывала позже, и запасные адреса не использовались никогда.
  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    // Если используется прокси, подключаемся к нему.
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }

    var cancelled = false;
    final socket = _connectAny(uri.host, uri.port, () => cancelled);
    return ConnectionTask.fromSocket(socket, () => cancelled = true);
  }

  /// Готовый сокет к [host]:[port] с тем же перебором адресов.
  Future<Socket> connectHost(String host, int port) =>
      _connectAny(host, port, () => false);

  static const perAddressTimeout = Duration(seconds: 6);
  static const _maxAttempts = 6;

  Future<Socket> _connectAny(
    String host,
    int port,
    bool Function() cancelled,
  ) async {
    Object? lastError;
    final tried = <String>{};

    Future<Socket?> tryAll(Iterable<InternetAddress> addresses) async {
      for (final address in addresses) {
        if (cancelled() || tried.length >= _maxAttempts) return null;
        if (!tried.add(address.address)) continue;
        try {
          return await Socket.connect(
            address,
            port,
            timeout: perAddressTimeout,
          );
        } catch (error) {
          lastError = error;
        }
      }
      return null;
    }

    final viaDoh = await tryAll(await lookup(host));
    if (viaDoh != null) return viaDoh;

    // Ответ из кэша мог устареть: сбрасываем и пробуем системный DNS.
    removeFromCache(host);
    try {
      final viaSystem = await tryAll(
        _ipv4First(await InternetAddress.lookup(host)),
      );
      if (viaSystem != null) return viaSystem;
    } catch (error) {
      lastError = error;
    }

    throw lastError ?? SocketException('Не удалось подключиться к $host');
  }

  void clearCache() {
    _cache.clear();
  }

  void removeFromCache(String host) {
    _cache.remove(host.toLowerCase());
  }
}

class _Entry {
  const _Entry(
    this.addresses,
    this.expires,
  );

  final List<InternetAddress> addresses;
  final DateTime expires;
}