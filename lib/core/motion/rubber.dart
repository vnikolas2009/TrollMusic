/// Резиновое сопротивление: внутри `[min, max]` значение не меняется,
/// за границей оно растёт всё медленнее и никогда не уходит дальше чем на
/// [limit] от края (та же формула, что в Rubber Dock).
double rubberBand(double x, double min, double max, {double limit = 46}) {
  if (x < min) return min - (1 - 1 / ((min - x) * 0.55 / limit + 1)) * limit;
  if (x > max) return max + (1 - 1 / ((x - max) * 0.55 / limit + 1)) * limit;
  return x;
}
