/// Действие по горизонтальному свайпу в плеере.
enum TrackSwipe { none, next, previous }

/// Минимальная скорость свайпа, px/с: медленные сдвиги не считаются.
const double trackSwipeMinVelocity = 350;

/// Свайп влево — следующий трек, вправо — предыдущий.
TrackSwipe trackSwipeFor(double? velocityX) {
  final v = velocityX ?? 0;
  if (v <= -trackSwipeMinVelocity) return TrackSwipe.next;
  if (v >= trackSwipeMinVelocity) return TrackSwipe.previous;
  return TrackSwipe.none;
}
