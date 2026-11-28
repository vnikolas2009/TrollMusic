/// Решает, когда трек считать прослушанным для статистики.
///
/// Прослушивание засчитывается один раз за запуск трека, когда реально
/// проиграно не меньше [threshold]: 30 секунд или половина трека, если он
/// короче минуты. Перемотка, пауза, повторные уведомления о том же треке
/// (перестановка очереди, перемешивание) и быстрые пропуски не считаются.
class PlayCounter {
  PlayCounter({required this.onPlay});

  /// Вызывается один раз, когда прослушивание засчитано.
  final void Function(String trackId) onPlay;

  static const _fullThreshold = Duration(seconds: 30);
  static const _minThreshold = Duration(seconds: 5);

  /// Скачок позиции больше этого значения считается перемоткой, а не
  /// проигрыванием.
  static const _maxStep = Duration(seconds: 2);

  String? _id;
  Duration? _duration;
  Duration _played = Duration.zero;
  Duration? _lastPosition;
  bool _counted = false;

  /// Идентификатор текущего трека.
  String? get currentId => _id;

  /// Сколько нужно проиграть, чтобы засчитать трек длиной [duration].
  static Duration threshold(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return _fullThreshold;
    final half = duration ~/ 2;
    if (half >= _fullThreshold) return _fullThreshold;
    return half < _minThreshold ? _minThreshold : half;
  }

  /// Начался трек. Повторный вызов с тем же [id] ничего не меняет, пока
  /// трек не запущен заново ([restart]).
  void startTrack(String? id, Duration? duration) {
    if (id == _id) {
      _duration ??= duration;
      return;
    }
    _reset(id, duration);
  }

  /// Тот же трек запущен с начала (повтор одного трека).
  void restart() => _reset(_id, _duration);

  void _reset(String? id, Duration? duration) {
    _id = id;
    _duration = duration;
    _played = Duration.zero;
    _lastPosition = null;
    _counted = false;
  }

  /// Очередное значение позиции плеера.
  void tick(Duration position, {required bool playing}) {
    final id = _id;
    if (id == null) return;
    final last = _lastPosition;

    // Трек доиграл до конца и пошёл по кругу: считаем как новый запуск.
    final duration = _duration;
    if (_counted &&
        last != null &&
        duration != null &&
        last >= duration - const Duration(seconds: 2) &&
        position < const Duration(seconds: 2)) {
      _reset(id, duration);
    }

    if (!playing) {
      _lastPosition = null;
      return;
    }
    _lastPosition = position;
    if (_counted || last == null) return;

    final step = position - last;
    if (step > Duration.zero && step <= _maxStep) _played += step;

    if (_played >= threshold(_duration)) {
      _counted = true;
      onPlay(id);
    }
  }
}
