import 'dart:isolate';

/// Тела короче этого порога разбираются сразу: запуск изолята дороже.
const _inlineLimit = 16 * 1024;

/// Выполняет [parse] в отдельном изоляте для больших ответов.
///
/// [parse] должна быть top-level или static функцией: замыкание с `this`
/// нельзя передать между изолятами.
Future<R> parseJson<R>(String body, R Function(String body) parse) {
  if (body.length < _inlineLimit) return Future.value(parse(body));
  return Isolate.run(() => parse(body));
}
