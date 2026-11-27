/// Сохранённая очередь после фильтрации недоступных треков.
typedef RestoredQueue = ({List<String> ids, int index, bool sameTrack});

/// Сколько треков очереди сохраняется между запусками.
const maxSavedQueue = 500;

/// Ограничивает очередь окном вокруг текущего трека, чтобы запись в
/// настройках не росла бесконечно. Возвращает ids и новый индекс.
({List<String> ids, int index}) trimQueue(List<String> ids, int index, {int max = maxSavedQueue}) {
  if (ids.isEmpty) return (ids: const [], index: 0);
  final current = index.clamp(0, ids.length - 1);
  if (ids.length <= max) return (ids: ids, index: current);

  var start = current - max ~/ 2;
  if (start < 0) start = 0;
  if (start + max > ids.length) start = ids.length - max;
  return (ids: ids.sublist(start, start + max), index: current - start);
}

/// Восстановление очереди: удаляет недоступные треки и подбирает индекс.
/// Если сохранённый текущий трек пропал, берётся ближайший следующий
/// (иначе предыдущий); [sameTrack] тогда `false` — позицию внутри трека
/// сохранять нельзя.
RestoredQueue restoreQueue({
  required List<String> savedIds,
  required int savedIndex,
  required bool Function(String id) isAvailable,
}) {
  if (savedIds.isEmpty) return (ids: const [], index: 0, sameTrack: false);

  final current = savedIndex.clamp(0, savedIds.length - 1);
  final kept = <String>[];
  var newIndex = -1;
  var same = false;

  for (var i = 0; i < savedIds.length; i++) {
    if (!isAvailable(savedIds[i])) continue;
    kept.add(savedIds[i]);
    if (newIndex < 0 && i >= current) {
      newIndex = kept.length - 1;
      same = i == current;
    }
  }

  if (kept.isEmpty) return (ids: const [], index: 0, sameTrack: false);
  if (newIndex < 0) newIndex = kept.length - 1; // после текущего ничего нет
  return (ids: kept, index: newIndex, sameTrack: same);
}
