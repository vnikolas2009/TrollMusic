import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:trollmusic/core/network/proxy.dart';
import 'package:trollmusic/core/network/worker_health.dart';
import 'package:trollmusic/core/storage/settings.dart';

/// Подменяет транспорт Dio: сеть в тестах не нужна.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late Settings settings;
  late ProxyConfig proxy;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('trollmusic-test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    box = await Hive.openBox<dynamic>('settings-${DateTime.now().microsecondsSinceEpoch}');
    settings = Settings(box);
    proxy = ProxyConfig(settings);
  });

  tearDown(() async => box.deleteFromDisk());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('ProxyConfig audio candidates', () {
    test('no worker keeps the direct url only', () {
      expect(proxy.hasWorker, isFalse);
      expect(proxy.audioVariants('https://rr1---sn.googlevideo.com/a'),
          ['https://rr1---sn.googlevideo.com/a']);
      expect(proxy.passthrough('https://x/y').toString(), 'https://x/y');
    });

    test('worker is appended after the direct url by default', () {
      settings.workerUrl = 'https://w.example.dev/';
      final variants = proxy.audioVariants('https://rr1---sn.googlevideo.com/a');
      expect(variants.length, 2);
      expect(variants.first, 'https://rr1---sn.googlevideo.com/a');
      expect(variants.last, startsWith('https://w.example.dev/proxy?url='));
      expect(
        Uri.parse(variants.last).queryParameters['url'],
        'https://rr1---sn.googlevideo.com/a',
      );
    });

    test('preferWorker puts the proxied url first', () {
      settings.workerUrl = 'https://w.example.dev';
      final variants = proxy.audioVariants(
        'https://rr1---sn.googlevideo.com/a',
        preferWorker: true,
      );
      expect(variants.first, startsWith('https://w.example.dev/proxy?url='));
      expect(variants.last, 'https://rr1---sn.googlevideo.com/a');
    });

    test('stream url points at the worker /stream route', () {
      settings.workerUrl = 'https://w.example.dev';
      final uri = proxy.stream('dQw4w9WgXcQ');
      expect(uri.path, '/stream');
      expect(uri.queryParameters['v'], 'dQw4w9WgXcQ');
      expect(uri.host, 'w.example.dev');
    });

    test('empty url is never wrapped', () {
      settings.workerUrl = 'https://w.example.dev';
      expect(proxy.audioVariants(''), ['']);
    });
  });

  group('WorkerStatus', () {
    test('labels describe the current state', () {
      expect(const WorkerStatus(configured: false, ok: false).label,
          'Worker не указан');
      expect(
        const WorkerStatus(configured: true, ok: true, latencyMs: 120).label,
        'Worker доступен · 120 мс',
      );
      expect(
        const WorkerStatus(configured: true, ok: true).label,
        'Worker доступен',
      );
      expect(
        const WorkerStatus(
          configured: true,
          ok: false,
          detail: 'нет соединения',
        ).label,
        'Worker недоступен · нет соединения',
      );
    });
  });

  group('WorkerHealth', () {
    test('not configured means unusable and no request is made', () async {
      final adapter = _StubAdapter((_) async => _json({'ok': true}));
      final dio = Dio()..httpClientAdapter = adapter;
      final health = WorkerHealth(settings: settings, proxy: proxy, dio: dio);

      final status = await health.check(force: true);

      expect(status.configured, isFalse);
      expect(status.ok, isFalse);
      expect(health.usable, isFalse);
      expect(adapter.calls, 0);
    });

    test('successful check marks the worker usable and is cached', () async {
      settings.workerUrl = 'https://w.example.dev';
      final adapter = _StubAdapter((_) async => _json({'ok': true}));
      final dio = Dio()..httpClientAdapter = adapter;
      final health = WorkerHealth(settings: settings, proxy: proxy, dio: dio);

      final status = await health.check(force: true);

      expect(status.ok, isTrue);
      expect(status.configured, isTrue);
      expect(health.usable, isTrue);
      expect(adapter.calls, 1);

      await health.check();
      expect(adapter.calls, 1, reason: 'health result should be cached');
    });

    test('two consecutive failures suspend the worker', () async {
      settings.workerUrl = 'https://w.example.dev';
      final adapter = _StubAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'stub down',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final health = WorkerHealth(settings: settings, proxy: proxy, dio: dio);

      await health.check(force: true);
      expect(health.isSuspended, isFalse);
      expect(health.usable, isTrue, reason: 'one failure is tolerated');

      await health.check(force: true);
      expect(health.status.ok, isFalse);
      expect(health.status.detail, 'нет соединения');
      expect(health.isSuspended, isTrue);
      expect(health.usable, isFalse);
    });

    test('reportSuccess lifts the suspension', () async {
      settings.workerUrl = 'https://w.example.dev';
      final adapter = _StubAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'stub down',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final health = WorkerHealth(settings: settings, proxy: proxy, dio: dio);

      await health.check(force: true);
      await health.check(force: true);
      expect(health.usable, isFalse);

      health.reportSuccess();
      expect(health.isSuspended, isFalse);
      expect(health.usable, isTrue);
      expect(health.status.ok, isTrue);
    });

    test('reset clears status and suspension', () async {
      settings.workerUrl = 'https://w.example.dev';
      final adapter = _StubAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'stub down',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final health = WorkerHealth(settings: settings, proxy: proxy, dio: dio);

      await health.check(force: true);
      await health.check(force: true);
      health.reset();

      expect(health.status, WorkerStatus.unknown);
      expect(health.isSuspended, isFalse);
    });
  });
}