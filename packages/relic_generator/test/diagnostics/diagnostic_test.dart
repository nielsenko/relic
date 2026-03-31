import 'package:relic_generator/relic_generator.dart';
import 'package:test/test.dart';

void main() {
  group('GeneratorDiagnostic', () {
    test('toString includes severity and message', () {
      const diag = GeneratorDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Missing @Path parameter',
      );
      expect(diag.toString(), contains('error'));
      expect(diag.toString(), contains('Missing @Path parameter'));
    });

    test('toString includes element name when provided', () {
      const diag = GeneratorDiagnostic(
        severity: DiagnosticSeverity.warning,
        message: 'Some warning',
        elementName: 'UsersApi.list',
      );
      expect(diag.toString(), contains('UsersApi.list'));
    });

    test('toString omits element name when not provided', () {
      const diag = GeneratorDiagnostic(
        severity: DiagnosticSeverity.info,
        message: 'Some info',
      );
      final str = diag.toString();
      expect(str, contains('info'));
      expect(str, contains('Some info'));
      expect(str, isNot(contains('(at')));
    });

    test('severity levels', () {
      expect(DiagnosticSeverity.values, hasLength(3));
      expect(DiagnosticSeverity.values, contains(DiagnosticSeverity.error));
      expect(DiagnosticSeverity.values, contains(DiagnosticSeverity.warning));
      expect(DiagnosticSeverity.values, contains(DiagnosticSeverity.info));
    });

    test('stores suggestion', () {
      const diag = GeneratorDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Bad type',
        suggestion: 'Use Request instead',
      );
      expect(diag.suggestion, 'Use Request instead');
    });
  });
}
