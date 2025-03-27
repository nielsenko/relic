import 'package:test/test.dart';
import 'package:relic/src/headers/standard_headers_extensions.dart';
import 'package:relic/src/relic_server.dart';

import '../headers_test_utils.dart';
import '../docs/strict_validation_docs.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cross-Origin-Opener-Policy
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group('Given a Cross-Origin-Opener-Policy header with the strict flag true',
      () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: true);
    });

    tearDown(() => server.close());

    test(
      'when an empty Cross-Origin-Opener-Policy header is passed then the server should respond with a bad request '
      'including a message that states the value cannot be empty',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'cross-origin-opener-policy': ''},
          ),
          throwsA(isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            contains('Value cannot be empty'),
          )),
        );
      },
    );

    test(
      'when an invalid Cross-Origin-Opener-Policy header is passed then the server should respond with a bad request '
      'including a message that states the value is invalid',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'cross-origin-opener-policy': 'custom-policy'},
          ),
          throwsA(isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            contains('Invalid value'),
          )),
        );
      },
    );

    test(
      'when a Cross-Origin-Opener-Policy header with an invalid value is passed '
      'then the server does not respond with a bad request if the headers '
      'is not actually used',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'cross-origin-opener-policy': 'custom-policy'},
          eagerParseHeaders: false,
        );
        expect(headers, isNotNull);
      },
    );

    test(
      'when a valid Cross-Origin-Opener-Policy header is passed then it should parse the policy correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'cross-origin-opener-policy': 'same-origin'},
        );

        expect(headers.crossOriginOpenerPolicy?.policy, equals('same-origin'));
      },
    );

    test(
      'when no Cross-Origin-Opener-Policy header is passed then it should return null',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {},
        );

        expect(headers.crossOriginOpenerPolicy, isNull);
      },
    );
  });

  group('Given a Cross-Origin-Opener-Policy header with the strict flag false',
      () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    group('When an empty Cross-Origin-Opener-Policy header is passed', () {
      test(
        'then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {},
          );
          expect(headers.crossOriginOpenerPolicy, isNull);
        },
      );

      test(
        'then it should be recorded in the "failedHeadersToParse" field',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'cross-origin-opener-policy': ''},
          );

          expect(
            headers.failedHeadersToParse['cross-origin-opener-policy'],
            equals(['']),
          );
        },
      );
    });
  });
}
