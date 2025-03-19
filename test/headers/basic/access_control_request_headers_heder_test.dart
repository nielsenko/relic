import 'package:relic/src/headers/standard_header_extensions.dart';
import 'package:relic/src/relic_server.dart';
import 'package:test/test.dart';

import '../docs/strict_validation_docs.dart';
import '../headers_test_utils.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Request-Headers
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group(
      'Given an Access-Control-Request-Headers header with the strict flag true',
      () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: true);
    });

    tearDown(() => server.close());

    test(
      'when an empty Access-Control-Request-Headers header is passed then the '
      'server responds with a bad request including a message that states the '
      'header value cannot be empty',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'access-control-request-headers': ''},
          ),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.message,
              'message',
              contains('Value cannot be empty'),
            ),
          ),
        );
      },
    );

    test(
      'when an Access-Control-Request-Headers header with an empty value is '
      'passed then the server does not respond with a bad request if the '
      'headers is not actually used',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'access-control-request-headers': ''},
          eagerParseHeaders: false,
        );

        expect(headers, isNotNull);
      },
    );

    test(
      'when an Access-Control-Request-Headers header is passed then it '
      'should parse the headers correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {
            'access-control-request-headers':
                'X-Custom-Header, X-Another-Header'
          },
        );

        expect(
          headers.accessControlRequestHeaders,
          equals(['X-Custom-Header', 'X-Another-Header']),
        );
      },
    );

    test(
      'when an Access-Control-Request-Headers header with extra whitespace is '
      'passed then it should parse the headers correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {
            'access-control-request-headers':
                ' X-Custom-Header , X-Another-Header '
          },
        );

        expect(
          headers.accessControlRequestHeaders,
          equals(['X-Custom-Header', 'X-Another-Header']),
        );
      },
    );

    test(
      'when an Access-Control-Request-Headers header with duplicate headers is '
      'passed then it should parse the headers correctly and remove duplicates',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {
            'access-control-request-headers':
                'X-Custom-Header, X-Another-Header, X-Custom-Header'
          },
        );

        expect(
          headers.accessControlRequestHeaders,
          equals(['X-Custom-Header', 'X-Another-Header']),
        );
      },
    );

    test(
      'when no Access-Control-Request-Headers header is passed then it should '
      'default to null',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {},
        );

        expect(headers.accessControlRequestHeaders, isNull);
      },
    );
  });

  group(
      'Given an Access-Control-Request-Headers header with the strict flag false',
      () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    group('when an empty Access-Control-Request-Headers header is passed', () {
      test(
        'then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'access-control-request-headers': ''},
          );

          expect(headers.accessControlRequestHeaders, isNull);
        },
      );

      test(
        'then it should be recorded in "failedHeadersToParse" field',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'access-control-request-headers': ''},
          );

          expect(
            headers.failedHeadersToParse['access-control-request-headers'],
            equals(['']),
          );
        },
      );
    });
  });
}
