import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/track_swipe.dart';

void main() {
  test('свайп влево — следующий, вправо — предыдущий', () {
    expect(trackSwipeFor(-800), TrackSwipe.next);
    expect(trackSwipeFor(800), TrackSwipe.previous);
  });

  test('медленный сдвиг и отсутствие скорости игнорируются', () {
    expect(trackSwipeFor(-100), TrackSwipe.none);
    expect(trackSwipeFor(100), TrackSwipe.none);
    expect(trackSwipeFor(0), TrackSwipe.none);
    expect(trackSwipeFor(null), TrackSwipe.none);
  });

  test('порог включается ровно на минимальной скорости', () {
    expect(trackSwipeFor(-trackSwipeMinVelocity), TrackSwipe.next);
    expect(trackSwipeFor(trackSwipeMinVelocity - 1), TrackSwipe.none);
  });
}
