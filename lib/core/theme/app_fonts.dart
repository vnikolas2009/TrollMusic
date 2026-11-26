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

  /// Семейство из `pubspec.yaml`.
  final String family;

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
