import 'dart:convert';

import 'package:relic/src/headers/typed/headers/authorization_header.dart';
import 'package:test/test.dart';
import 'package:relic/src/headers/headers.dart';
import 'package:relic/src/relic_server.dart';

import '../headers_test_utils.dart';
import '../docs/strict_validation_docs.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Proxy-Authorization
/// About empty value test, check the [StrictValidationDocs] class for more details.
void main() {
  group('Given a Proxy-Authorization header with the strict flag true', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: true);
    });

    tearDown(() => server.close());

    test(
      'when an empty Proxy-Authorization header is passed then the server '
      'responds with a bad request including a message that states the header '
      'value cannot be empty',
      () async {
        expect(
          () async => await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': ''},
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
      'when a Proxy-Authorization header with an invalid value is passed '
      'then the server does not respond with a bad request if the headers '
      'is not actually used',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {
            'proxy-authorization': 'invalid-proxy-authorization-format'
          },
          parseAllHeaders: false,
        );

        expect(headers, isNotNull);
      },
    );

    test(
      'when no Proxy-Authorization header is passed then it should default to null',
      () async {
        Headers headers = await getServerRequestHeaders(
          server: server,
          headers: {},
        );

        expect(headers.proxyAuthorization, isNull);
      },
    );

    group('and a Bearer Authorization header', () {
      test(
        'when an invalid Bearer token is passed then the server responds with a '
        'bad request including a message that states the token format is invalid',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'proxy-authorization': 'Bearer'},
            ),
            throwsA(
              isA<BadRequestException>().having(
                (e) => e.message,
                'message',
                contains('Invalid bearer prefix'),
              ),
            ),
          );
        },
      );

      test(
        'when a Bearer token is passed then it should parse the token correctly',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'Bearer validToken123'},
          );

          expect(
            headers.proxyAuthorization,
            isA<BearerAuthorizationHeader>().having(
              (auth) => auth.token,
              'token',
              'validToken123',
            ),
          );
        },
      );
    });

    group('and a Basic Authorization header', () {
      test(
        'when an invalid Basic token is passed then the server responds with a '
        'bad request including a message that states the token format is invalid',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'proxy-authorization': 'Basic invalidBase64'},
            ),
            throwsA(
              isA<BadRequestException>().having(
                (e) => e.message,
                'message',
                contains('Invalid basic token format'),
              ),
            ),
          );
        },
      );

      test(
        'when a Basic token is passed then it should parse the credentials '
        'correctly',
        () async {
          final credentials = base64Encode(utf8.encode('user:pass'));
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'Basic $credentials'},
          );

          expect(
            headers.proxyAuthorization,
            isA<BasicAuthorizationHeader>()
                .having((auth) => auth.username, 'username', 'user')
                .having((auth) => auth.password, 'password', 'pass'),
          );
        },
      );
    });

    group('and a Digest Authorization header', () {
      test(
        'when an invalid Digest token is passed then the server responds with a '
        'bad request including a message that states the token format is invalid',
        () async {
          expect(
            () async => await getServerRequestHeaders(
              server: server,
              headers: {'proxy-authorization': 'Digest invalidFormat'},
            ),
            throwsA(
              isA<BadRequestException>().having(
                (e) => e.message,
                'message',
                contains('Invalid digest token format'),
              ),
            ),
          );
        },
      );

      group('when a Digest token is passed with missing', () {
        test(
          '"username" then the server responds with a bad request including '
          'a message that states the username is required',
          () async {
            final digestValue =
                'missingUsername="user", realm="realm", nonce="nonce", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Username is required and cannot be empty'),
                ),
              ),
            );
          },
        );
        test(
          '"realm" then the server responds with a bad request including '
          'a message that states the realm is required',
          () async {
            final digestValue =
                'username="user", missingRealm="realm", nonce="nonce", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Realm is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"nonce" then the server responds with a bad request including '
          'a message that states the nonce is required',
          () async {
            final digestValue =
                'username="user", realm="realm", missingNonce="nonce", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Nonce is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"uri" then the server responds with a bad request including '
          'a message that states the uri is required',
          () async {
            final digestValue =
                'username="user", realm="realm", nonce="nonce", missingUri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('URI is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"response" then the server responds with a bad request including '
          'a message that states the response is required',
          () async {
            final digestValue =
                'username="user", realm="realm", nonce="nonce", uri="/", missingResponse="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Response is required and cannot be empty'),
                ),
              ),
            );
          },
        );
      });

      group('when a Digest token is passed with empty', () {
        test(
          '"username" then the server responds with a bad request including '
          'a message that states the username is required',
          () async {
            final digestValue =
                'username="", realm="realm", nonce="nonce", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Username is required and cannot be empty'),
                ),
              ),
            );
          },
        );
        test(
          '"realm" then the server responds with a bad request including '
          'a message that states the realm is required',
          () async {
            final digestValue =
                'username="user", realm="", nonce="nonce", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Realm is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"nonce" then the server responds with a bad request including '
          'a message that states the nonce is required',
          () async {
            final digestValue =
                'username="user", realm="realm", nonce="", uri="/", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Nonce is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"uri" then the server responds with a bad request including '
          'a message that states the uri is required',
          () async {
            final digestValue =
                'username="user", realm="realm", nonce="nonce", uri="", response="response"';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('URI is required and cannot be empty'),
                ),
              ),
            );
          },
        );

        test(
          '"response" then the server responds with a bad request including '
          'a message that states the response is required',
          () async {
            final digestValue =
                'username="user", realm="realm", nonce="nonce", uri="/", response=""';

            expect(
              () async => await getServerRequestHeaders(
                server: server,
                headers: {'proxy-authorization': 'Digest $digestValue'},
              ),
              throwsA(
                isA<BadRequestException>().having(
                  (e) => e.message,
                  'message',
                  contains('Response is required and cannot be empty'),
                ),
              ),
            );
          },
        );
      });

      test(
        'when a Digest token is passed with all required parameters then it '
        'should parse the credentials correctly',
        () async {
          final digestValue =
              'username="user", realm="realm", nonce="nonce", uri="/", response="response"';
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'Digest $digestValue'},
          );

          expect(
              headers.proxyAuthorization,
              isA<DigestAuthorizationHeader>()
                  .having((auth) => auth.username, 'username', 'user')
                  .having((auth) => auth.realm, 'realm', 'realm')
                  .having((auth) => auth.nonce, 'nonce', 'nonce')
                  .having((auth) => auth.uri, 'uri', '/')
                  .having((auth) => auth.response, 'response', 'response'));
        },
      );

      test(
        'when a Digest token is passed then it should parse the credentials correctly',
        () async {
          final digestValue =
              'username="user", realm="realm", nonce="nonce", uri="/", response="response", algorithm="MD5", qop="auth", nc="00000001", cnonce="cnonce", opaque="opaque"';
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'Digest $digestValue'},
          );

          expect(
            headers.proxyAuthorization,
            isA<DigestAuthorizationHeader>()
                .having((auth) => auth.username, 'username', 'user')
                .having((auth) => auth.realm, 'realm', 'realm')
                .having((auth) => auth.nonce, 'nonce', 'nonce')
                .having((auth) => auth.uri, 'uri', '/')
                .having((auth) => auth.response, 'response', 'response')
                .having((auth) => auth.algorithm, 'algorithm', 'MD5')
                .having((auth) => auth.qop, 'qop', 'auth')
                .having((auth) => auth.nc, 'nc', '00000001')
                .having((auth) => auth.cnonce, 'cnonce', 'cnonce')
                .having((auth) => auth.opaque, 'opaque', 'opaque'),
          );
        },
      );
    });
  });

  group('Given a Proxy-Authorization header with the strict flag false', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    group('when an empty Proxy-Authorization header is passed', () {
      test(
        'then it should return null',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': ''},
          );

          expect(headers.proxyAuthorization, isNull);
        },
      );

      test(
        'then it should be recorded in "failedHeadersToParse" field',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': ''},
          );

          expect(
            headers.failedHeadersToParse['proxy-authorization'],
            equals(['']),
          );
        },
      );
    });

    group('when an invalid Proxy-Authorization header is passed', () {
      test(
        'then it should return null',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'InvalidFormat'},
          );

          expect(headers.proxyAuthorization, isNull);
        },
      );

      test(
        'then it should be recorded in "failedHeadersToParse" field',
        () async {
          Headers headers = await getServerRequestHeaders(
            server: server,
            headers: {'proxy-authorization': 'InvalidFormat'},
          );

          expect(
            headers.failedHeadersToParse['proxy-authorization'],
            equals(['InvalidFormat']),
          );
        },
      );
    });
  });
}
