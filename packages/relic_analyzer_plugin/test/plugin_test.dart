import 'package:relic_analyzer_plugin/relic_analyzer_plugin.dart';
import 'package:test/test.dart';

void main() {
  group('MultipleHttpMethodsRule', () {
    test('can be instantiated', () {
      final rule = MultipleHttpMethodsRule();
      expect(rule.name, 'relic_multiple_http_methods');
    });

    test('has correct diagnostic code', () {
      final rule = MultipleHttpMethodsRule();
      expect(rule.diagnosticCode.lowerCaseName, 'relic_multiple_http_methods');
    });
  });

  group('MultipleBodyParamsRule', () {
    test('can be instantiated', () {
      final rule = MultipleBodyParamsRule();
      expect(rule.name, 'relic_multiple_body_params');
    });

    test('has correct diagnostic code', () {
      final rule = MultipleBodyParamsRule();
      expect(rule.diagnosticCode.lowerCaseName, 'relic_multiple_body_params');
    });
  });
}
