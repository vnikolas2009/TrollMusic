import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/theme/app_fonts.dart';

void main() {
  group('BuiltInFont', () {
    test('идентификаторы уникальны и с префиксом', () {
      final ids = BuiltInFont.all.map((f) => f.id).toSet();
      expect(ids.length, BuiltInFont.all.length);
      for (final id in ids) {
        expect(id.startsWith(BuiltInFont.idPrefix), isTrue);
      }
    });

    test('byId находит встроенный шрифт и не путает с чужими', () {
      expect(BuiltInFont.byId(BuiltInFont.inter.id), BuiltInFont.inter);
      expect(BuiltInFont.byId('builtin:нет'), isNull);
      expect(BuiltInFont.byId('user_abc'), isNull);
      expect(BuiltInFont.byId(null), isNull);
    });
  });
}
