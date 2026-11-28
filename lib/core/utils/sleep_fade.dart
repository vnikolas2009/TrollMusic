/// Громкость перед остановкой по таймеру сна: до начала затухания — 1,
/// затем линейно падает до 0 к моменту остановки.
double sleepFadeVolume(Duration remaining, {Duration fade = const Duration(seconds: 45)}) {
  if (fade <= Duration.zero) return remaining > Duration.zero ? 1 : 0;
  if (remaining >= fade) return 1;
  if (remaining <= Duration.zero) return 0;
  return remaining.inMilliseconds / fade.inMilliseconds;
}
