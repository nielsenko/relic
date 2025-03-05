import 'package:test/test.dart';
import 'package:relic/src/headers/headers.dart';
import 'package:relic/src/relic_server.dart';
import '../headers_test_utils.dart';
import '../docs/strict_validation_docs.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Allow
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group('Given an Allow header with the strict flag true', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: true);
    });

    tearDown(() => server.close());

    test(
      'when an empty Allow header is passed then the server responds '
      'with a bad request including a message that states the header value '
      'cannot be empty',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'allow': ''},
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
      'when an invalid method is passed then the server responds '
      'with a bad request including a message that states the header value '
      'is invalid',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'allow': 'CUSTOM'},
          ),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.message,
              'message',
              contains('Invalid value'),
            ),
          ),
        );
      },
    );

    test(
      'when an Allow header with an invalid value is passed '
      'then the server does not respond with a bad request if the headers '
      'is not actually used',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {'allow': 'CUSTOM'},
          eagerParseHeaders: false,
        );

        expect(headers, isNotNull);
      },
    );

    test(
      'when a valid Allow header is passed then it should parse the methods correctly',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {'allow': 'GET, POST, DELETE'},
        );

        expect(
          headers.allow?.map((method) => method.value).toList(),
          equals(['GET', 'POST', 'DELETE']),
        );
      },
    );

    test(
      'when an Allow header with duplicate methods is passed then it should '
      'parse the methods correctly and remove duplicates',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {'allow': 'GET, POST, GET'},
        );

        expect(
          headers.allow?.map((method) => method.value).toList(),
          equals(['GET', 'POST']),
        );
      },
    );

    test(
      'when an Allow header with spaces is passed then it should parse the '
      'methods correctly',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {'allow': ' GET , POST , DELETE '},
        );

        expect(
          headers.allow?.map((method) => method.value).toList(),
          equals(['GET', 'POST', 'DELETE']),
        );
      },
    );
  });

  group('Given an Allow header with the strict flag false', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    group('when an empty Allow header is passed', () {
      test(
        'then it should return null',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'allow': ''},
          );

          expect(headers.allow, isNull);
        },
      );

      test(
        'then it should be recorded in "failedHeadersToParse" field',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'allow': ''},
          );

          expect(headers.failedHeadersToParse['allow'], equals(['']));
        },
      );
    });
  });
}
