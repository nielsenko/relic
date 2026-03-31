import 'package:relic_lean_builder/relic_lean_builder.dart';
import 'package:test/test.dart';

void main() {
  group('RelicGenerator', () {
    test('can be instantiated', () {
      final generator = RelicGenerator();
      expect(generator, isNotNull);
    });
  });
}
