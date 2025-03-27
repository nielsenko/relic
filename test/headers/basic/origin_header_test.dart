import 'package:relic/relic.dart';
import 'package:test/test.dart';
import 'package:relic/src/headers/standard_headers_extensions.dart';
import '../headers_test_utils.dart';
import '../docs/strict_validation_docs.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Origin
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group(
    'Given an Origin header with the strict flag true',
    skip: 'todo: drop strict mode',
    () {
      late RelicServer server;

      setUp(() async {
        server = await createServer(strictHeaders: true);
      });

      tearDown(() => server.close());

      test(
        'when an empty Origin header is passed then the server responds '
        'with a bad request including a message that states the header value '
        'cannot be empty',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'origin': ''},
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
        'when an Origin header with an invalid URI format is passed '
        'then the server responds with a bad request including a message that '
        'states the URI format is invalid',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'origin': 'h@ttp://example.com'},
            ),
            throwsA(
              isA<BadRequestException>().having(
                (e) => e.message,
                'message',
                contains('Invalid URI format'),
              ),
            ),
          );
        },
      );

      test(
        'when an Origin header with an invalid port number is passed '
        'then the server responds with a bad request including a message that '
        'states the URI format is invalid',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'origin': 'http://example.com:test'},
            ),
            throwsA(
              isA<BadRequestException>().having(
                (e) => e.message,
                'message',
                contains('Invalid URI format'),
              ),
            ),
          );
        },
      );

      test(
        'when an Origin header with an invalid origin format is passed '
        'then the server does not respond with a bad request if the headers '
        'is not actually used',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': 'http://example.com:test'},
            eagerParseHeaders: false,
          );

          expect(headers, isNotNull);
        },
      );

      test(
        'when a valid Origin header is passed then it should parse the URI correctly',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': 'https://example.com'},
          );

          expect(
            headers.origin,
            equals(Uri.parse('https://example.com')),
          );
        },
      );

      test(
        'when a valid Origin header is passed with a port number then it should parse the port number correctly',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': 'https://example.com:8080'},
          );

          expect(
            headers.origin?.port,
            equals(8080),
          );
        },
      );

      test(
        'when an Origin header with extra whitespace is passed then it should parse the URI correctly',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': ' https://example.com '},
          );

          expect(
            headers.origin,
            equals(Uri.parse('https://example.com')),
          );
        },
      );

      test(
        'when no Origin header is passed then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {},
          );

          expect(headers.origin_.valueOrNullIfInvalid, isNull);
          expect(() => headers.origin, throwsA(isA<InvalidHeaderException>()));
        },
      );
    },
  );

  group('Given an Origin header with the strict flag false', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());
    group('when an empty Origin header is passed', () {
      test(
        'then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': ''},
          );
          expect(headers.origin_.valueOrNullIfInvalid, isNull);
          expect(() => headers.origin, throwsA(isA<InvalidHeaderException>()));
        },
      );
    });

    group('when an invalid Origin header is passed', () {
      test(
        'then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'origin': 'h@ttp://example.com'},
          );

          expect(headers.origin_.valueOrNullIfInvalid, isNull);
          expect(() => headers.origin, throwsA(isA<InvalidHeaderException>()));
        },
      );
    });
  });
}
