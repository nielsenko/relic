import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  group('DigestAuthorizationHeader.parse with bare tokens', () {
    group('Given a wire value with unquoted algorithm/qop/nc,', () {
      test('when parsed, '
          'then the token-form parameters are captured.', () {
        final header = DigestAuthorizationHeader.parse(
          'username="user", realm="realm", nonce="n", uri="/", '
          'response="r", algorithm=MD5, qop=auth, nc=00000001',
        );

        expect(header.algorithm, equals('MD5'));
        expect(header.qop, equals('auth'));
        expect(header.nc, equals('00000001'));
      });
    });

    group('Given a bare auth-param value that is not a token,', () {
      test('when parsed, '
          'then it throws a FormatException.', () {
        expect(
          () => DigestAuthorizationHeader.parse(
            'username="user", realm="r", nonce="n", uri="/", '
            'response="r", algorithm=MD5;evil',
          ),
          throwsFormatException,
        );
      });
    });
  });

  group('DigestAuthorizationHeader.parse with adversarial input', () {
    group('Given a long value containing no auth-param separators,', () {
      test('when parsed, '
          'then it is rejected without super-linear backtracking.', () {
        final value = 'a' * 32000;

        final stopwatch = Stopwatch()..start();
        expect(
          () => DigestAuthorizationHeader.parse(value),
          throwsFormatException,
        );
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Parsing must be linear in the length of the value',
        );
      });
    });

    group('Given a value with unparsable text between auth-params,', () {
      test('when parsed, '
          'then the value is rejected rather than the text being skipped.', () {
        expect(
          () => DigestAuthorizationHeader.parse(
            'username="u", realm="r" GARBAGE, nonce="n", '
            'uri="/", response="abc"',
          ),
          throwsFormatException,
        );
      });
    });
  });
}
