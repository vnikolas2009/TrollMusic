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

    for (final endpoint in _endpoints) {
      try {
        final results = await Future.wait([
          _query(endpoint, host, 'A'),
          _query(endpoint, host, 'AAAA'),
        ]).timeout(AppConfig.dohTimeout);

        for (final result in results) {
          addresses.addAll(result.addresses);

          if (result.addresses.isNotEmpty &&
              result.ttl < minTtl) {
            minTtl = result.ttl;
          }
        }

        if (addresses.isNotEmpty) {
          break;
        }
      } catch (_) {
        // Переходим к следующему DoH-серверу.
      }
    }

    final unique = <String, InternetAddress>{};

    for (final address in addresses) {
      unique[address.address] = address;
    }

    if (unique.isNotEmpty) {
      final result = unique.values.toList();

      _cache[host] = _Entry(
        result,
        DateTime.now().add(
          Duration(seconds: minTtl.clamp(60, 900)),
        ),
      );

      return result;
    }

    // Последняя попытка — системный DNS.
    return InternetAddress.lookup(host);
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
  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    // Если используется прокси, подключаемся к нему.
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(
        proxyHost,
        proxyPort,
      );
    }

    final addresses = await lookup(uri.host);

    Object? lastError;

    for (final address in addresses) {
      try {
        final task = await Socket.startConnect(
          address,
          uri.port,
        ).timeout(AppConfig.connectTimeout);

        return task;
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        SocketException(
          'DoH: no addresses for ${uri.host}',
        );
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