import 'package:relic/relic.dart';
import 'package:test/test.dart';
import 'package:relic/src/headers/standard_headers_extensions.dart';

import '../headers_test_utils.dart';
import '../docs/strict_validation_docs.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group('Given a Content-Range header with the strict flag true',
      skip: 'drop strict mode', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: true);
    });

    tearDown(() => server.close());

    test(
      'when an empty Content-Range header is passed then the server responds '
      'with a bad request including a message that states the header value '
      'cannot be empty',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'content-range': ''},
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
      'when an invalid Content-Range header with non-numeric characters is passed '
      'then the server responds with a bad request including a message that '
      'states the header value has an invalid format',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'content-range': 'bytes 0-abc/1234'},
          ),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.message,
              'message',
              contains('Invalid format'),
            ),
          ),
        );
      },
    );

    test(
      'when an invalid Content-Range header with negative numbers is passed then '
      'the server responds with a bad request including a message that '
      'states the header value has an invalid format',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'content-range': 'bytes -10-499/1234'},
          ),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.message,
              'message',
              contains('Invalid format'),
            ),
          ),
        );
      },
    );

    test(
      'when an invalid Content-Range header with start greater than end is '
      'passed then the server responds with a bad request including a message '
      'that states the header value has an invalid range',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'content-range': 'bytes 500-499/1234'},
          ),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.message,
              'message',
              contains('Invalid range'),
            ),
          ),
        );
      },
    );

    test(
      'when a Content-Range header with an invalid value is passed '
      'then the server does not respond with a bad request if the headers '
      'is not actually used',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'content-range': 'bytes 500-499/1234'},
          eagerParseHeaders: false,
        );

        expect(headers, isNotNull);
      },
    );

    test(
      'when a Content-Range header with a valid byte range is passed then it '
      'should parse correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'content-range': 'bytes 0-499/1234'},
        );

        expect(headers.contentRange?.unit, equals('bytes'));
        expect(headers.contentRange?.start, equals(0));
        expect(headers.contentRange?.end, equals(499));
        expect(headers.contentRange?.size, equals(1234));
      },
    );

    test(
      'when a Content-Range header with a valid byte range and unknown size is '
      'passed then it should parse correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'content-range': 'bytes 0-499/*'},
        );

        expect(headers.contentRange?.unit, equals('bytes'));
        expect(headers.contentRange?.start, equals(0));
        expect(headers.contentRange?.end, equals(499));
        expect(headers.contentRange?.size, isNull);
      },
    );

    test(
      'when a Content-Range header with a valid unsatisfiable range is passed '
      'then it should parse correctly',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {'content-range': 'bytes */1234'},
        );

        expect(headers.contentRange?.unit, equals('bytes'));
        expect(headers.contentRange?.start, isNull);
        expect(headers.contentRange?.end, isNull);
        expect(headers.contentRange?.size, equals(1234));
      },
    );

    test(
      'when no Content-Range header is passed then it should return null',
      () async {
        var headers = await getServerRequestHeaders(
          server: server,
          headers: {},
        );

        expect(headers.contentRange_.valueOrNullIfInvalid, isNull);
        expect(
            () => headers.contentRange, throwsA(isA<InvalidHeaderException>()));
      },
    );
  });

  group('Given a Content-Range header with the strict flag false', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    group('when an invalid Content-Range header is passed', () {
      test(
        'then it should return null',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'content-range': 'bytes 0-499/invalid'},
          );

          expect(headers.contentRange_.valueOrNullIfInvalid, isNull);
          expect(() => headers.contentRange,
              throwsA(isA<InvalidHeaderException>()));
        },
      );

      test(
        'then it should be recorded in the "failedHeadersToParse" field',
        skip: 'todo: drop failedHeadersToParse',
        () async {
          var headers = await getServerRequestHeaders(
            server: server,
            headers: {'content-range': 'bytes 0-499/invalid'},
          );

          expect(
            headers.failedHeadersToParse['content-range'],
            equals(['bytes 0-499/invalid']),
          );
        },
      );
    });
  });
}
