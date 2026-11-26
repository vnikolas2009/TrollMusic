/// Встроенный шрифт приложения (поставляется в assets, лицензия OFL).
class BuiltInFont {
  const BuiltInFont({
    required this.id,
    required this.name,
    required this.description,
    required this.family,
  });

  /// Идентификатор для настроек, всегда с префиксом [idPrefix].
  final String id;
  final String name;
  final String description;

  /// Базовое семейство из `pubspec.yaml` (обычная толщина).
  final String family;

  /// Названия уровней толщины: сдвиг начертаний на 0–3 шага вверх или вниз.
  static const weightLevels = ['Тонкий', 'Обычный', 'Плотный', 'Жирный'];

  /// Уровень по умолчанию — [weightLevels] `[1]`, «Обычный».
  static const defaultWeightLevel = 1;

  /// Семейство для уровня толщины. Все уровни собраны в `pubspec.yaml` из
  /// одних и тех же файлов, у каждого вес 400–800 сдвинут на шаг: у «Жирного»
  /// обычный текст рисуется начертанием 600, а заголовки — 800.
  String familyFor(int level) {
    final l = level.clamp(0, weightLevels.length - 1);
    return l == defaultWeightLevel ? family : '$family-w$l';
  }

  static const idPrefix = 'builtin:';

  static const manrope = BuiltInFont(
    id: '${idPrefix}manrope',
    name: 'Manrope',
    description: 'Современный геометричный, плотный и выразительный',
    family: 'Manrope',
  );

  static const inter = BuiltInFont(
    id: '${idPrefix}inter',
    name: 'Inter',
    description: 'Минималистичный, нейтральный и очень читаемый',
    family: 'Inter',
  );

  /// Порядок в списке выбора: сначала выразительный, затем нейтральный.
  static const all = [manrope, inter];

  /// Встроенный шрифт по идентификатору или `null`.
  static BuiltInFont? byId(String? id) {
    for (final font in all) {
      if (font.id == id) return font;
    }
    return null;
  }
}
