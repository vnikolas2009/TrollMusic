import 'dart:async';

/// Запускает все [tasks] одновременно и возвращает первый подходящий результат.
///
/// Ошибки отдельных задач игнорируются. Если ни одна задача не дала результат
/// (или вышел [timeout]) — возвращается `null`.
Future<T?> firstNonEmpty<T>(
  Iterable<Future<T?> Function()> tasks, {
  bool Function(T value)? accept,
  Duration? timeout,
}) {
  final list = tasks.toList();
  if (list.isEmpty) return Future<T?>.value(null);

  final completer = Completer<T?>();
  var pending = list.length;

  void settle() {
    pending--;
    if (pending == 0 && !completer.isCompleted) completer.complete(null);
  }

  for (final task in list) {
    Future<T?> future;
    try {
      future = task();
    } catch (_) {
      settle();
      continue;
    }
    future.then(
      (value) {
        if (value != null &&
            (accept?.call(value) ?? true) &&
            !completer.isCompleted) {
          completer.complete(value);
        }
        settle();
      },
      onError: (Object _) => settle(),
    );
  }

  if (timeout == null) return completer.future;
  return completer.future.timeout(timeout, onTimeout: () => null);
}

/// То же, что [firstNonEmpty], но для списков: возвращает первый непустой список.
Future<List<E>> firstNonEmptyList<E>(
  Iterable<Future<List<E>> Function()> tasks, {
  Duration? timeout,
}) async {
  final result = await firstNonEmpty<List<E>>(
    tasks,
    accept: (value) => value.isNotEmpty,
    timeout: timeout,
  );
  return result ?? <E>[];
}
