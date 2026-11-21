import 'dart:io';

import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/youtube/stream_candidate.dart';
import '../../core/utils/audio_pick.dart';
import '../../data/models/track.dart';

typedef StreamResolver = Future<List<StreamCandidate>> Function(
  Track track, {
  bool fresh,
});

/// Аудиоисточник, который получает прямую ссылку **в момент воспроизведения**.
///
/// Раньше ссылка бралась из сохранённого трека и к моменту нажатия «играть»
/// уже протухала — отсюда зависания и «играет только скачанное». Теперь очередь
/// собирается мгновенно, а ссылка разрешается лениво: при первом запросе плеера,
/// с перебором кандидатов и одной повторной попыткой со свежими ссылками.
class ResolvedStreamSource extends StreamAudioSource {
  ResolvedStreamSource({
    required this.track,
    required this.resolve,
    required this.dio,
    this.fresh = false,
    this.onResolved,
    super.tag,
  });

  final Track track;
  final StreamResolver resolve;
  final Dio dio;
  final void Function(Track track, StreamCandidate candidate)? onResolved;

  bool fresh;
  List<StreamCandidate>? _candidates;
  int _preferred = 0;

  Future<List<StreamCandidate>> _load({bool forceFresh = false}) async {
    final cached = _candidates;
    if (cached != null && !forceFresh) return cached;
    final list = await resolve(track, fresh: forceFresh || fresh);
    fresh = false;
    _candidates = list;
    _preferred = 0;
    return list;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    Object? lastError;
    for (var round = 0; round < 2; round++) {
      final list = await _load(forceFresh: round > 0);
      if (list.isEmpty) {
        lastError = StateError('Нет доступных аудиопотоков');
        continue;
      }
      final order = [...list.skip(_preferred), ...list.take(_preferred)];
      for (final candidate in order) {
        try {
          final response = await _open(candidate, start, end);
          _preferred = list.indexOf(candidate);
          onResolved?.call(track, candidate);
          return response;
        } catch (error) {
          lastError = error;
        }
      }
    }
    throw lastError ?? StateError('Не удалось открыть аудиопоток');
  }

  Future<StreamAudioResponse> _open(
    StreamCandidate candidate,
    int? start,
    int? end,
  ) async {
    final from = start ?? 0;
    final range = end == null ? 'bytes=$from-' : 'bytes=$from-${end - 1}';

    final response = await dio.get<ResponseBody>(
      candidate.url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...candidate.headers, 'Range': range},
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (code) => code != null && code < 500,
      ),
    );

    final code = response.statusCode ?? 0;
    final body = response.data;
    if (body == null || (code != 200 && code != 206)) {
      if (body != null) await _discard(body);
      throw HttpException('HTTP $code');
    }

    final total = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    final rangeInfo = parseContentRange(response.headers.value('content-range'));

    int? sourceLength;
    int contentLength;
    int offset;
    if (code == 206 && rangeInfo != null) {
      sourceLength = rangeInfo.total;
      contentLength = rangeInfo.end - rangeInfo.start + 1;
      offset = rangeInfo.start;
    } else {
      if (from > 0 || total == null) {
        await _discard(body);
        throw const HttpException('Сервер не поддерживает Range');
      }
      sourceLength = total;
      contentLength = total;
      offset = 0;
    }

    final headerType = response.headers.value(Headers.contentTypeHeader);
    final contentType = (headerType ?? candidate.mime)
        .split(';')
        .first
        .trim()
        .toLowerCase();

    return StreamAudioResponse(
      sourceLength: sourceLength,
      contentLength: contentLength,
      offset: offset,
      stream: body.stream,
      contentType: contentType.startsWith('audio/') ? contentType : 'audio/mp4',
    );
  }

  Future<void> _discard(ResponseBody body) async {
    try {
      await body.stream.listen((_) {}).cancel();
    } catch (_) {}
  }
}
