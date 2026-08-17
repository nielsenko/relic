import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionHeader.parse', () {
    group('Given an empty value,', () {
      test(
        'when parsed, '
        'then it throws a FormatException stating the value cannot be empty.',
        () {
          expect(
            () => ConnectionHeader.parse(['']),
            throwsA(
              isA<FormatException>().having(
                (final e) => e.message,
                'message',
                contains('Value cannot be empty'),
              ),
            ),
          );
        },
      );
    });

    group('Given an unknown directive,', () {
      test('when parsed, '
          'then it throws a FormatException stating the value is invalid.', () {
        expect(
          () => ConnectionHeader.parse(['custom-directive']),
          throwsA(
            isA<FormatException>().having(
              (final e) => e.message,
              'message',
              contains('Invalid value'),
            ),
          ),
        );
      });
    });
  });
}
