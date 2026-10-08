import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import 'conformance.dart';

/// How a response is framed on the wire is decided once, in the core, so
/// every adapter answers the same bytes for the same Response.
void framingTests(final AdapterConformance conformance) {
  RelicServer? server;

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  /// Everything the server writes back for [request], as text.
  Future<String> raw(final String request) async {
    final socket = await io.Socket.connect(
      io.InternetAddress.loopbackIPv4,
      server!.url.port,
    );
    socket.write(request);
    await socket.flush();
    final reply = await utf8
        .decodeStream(socket)
        .timeout(const Duration(seconds: 5));
    socket.destroy();
    return reply;
  }

  /// The reply split at the end of its first head.
  (String, String) split(final String reply) {
    final at = reply.indexOf('\r\n\r\n') + 4;
    return (reply.substring(0, at), reply.substring(at));
  }

  Future<void> serve(final Handler handler) async {
    server = await conformance.serve(handler);
  }

  Response ok(final Request _) => Response.ok(body: Body.fromString('ok'));

  group('Given the response framing', () {
    test('when a 204 carries a body on a keep-alive connection, '
        'then no body bytes precede the next response', () async {
      await serve(
        (final req) => req.url.path == '/no-content'
            ? Response(204, body: Body.fromString('x'))
            : ok(req),
      );

      final reply = await raw(
        'GET /no-content HTTP/1.1\r\nHost: x\r\n\r\n'
        'GET /ok HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, rest) = split(reply);
      expect(first, startsWith('HTTP/1.1 204'));
      expect(first.toLowerCase(), isNot(contains('content-length: 1')));
      expect(rest, startsWith('HTTP/1.1 200'));
      expect(rest, endsWith('ok'));
    });

    test('when a 304 carries a streamed body on a keep-alive connection, '
        'then no body bytes precede the next response', () async {
      await serve(
        (final req) => req.url.path == '/not-modified'
            ? Response(
                304,
                body: Body.fromDataStream(
                  Stream.value(Uint8List.fromList([120])),
                ),
              )
            : ok(req),
      );

      final reply = await raw(
        'GET /not-modified HTTP/1.1\r\nHost: x\r\n\r\n'
        'GET /ok HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, rest) = split(reply);
      expect(first, startsWith('HTTP/1.1 304'));
      expect(first.toLowerCase(), isNot(contains('transfer-encoding')));
      expect(rest, startsWith('HTTP/1.1 200'));
      expect(rest, endsWith('ok'));
    });

    test('when a HEAD is answered with a body of known length, '
        'then the length is announced and no body goes out', () async {
      await serve(ok);

      final reply = await raw(
        'HEAD / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, rest) = split(reply);
      expect(first, startsWith('HTTP/1.1 200'));
      expect(first.toLowerCase(), contains('content-length: 2'));
      expect(rest, isEmpty);
    });

    test("when a handler sets a Content-Length that is not the body's, "
        "then the body's length goes on the wire", () async {
      await serve(
        (final req) => Response.ok(
          body: Body.fromString('ok'),
          headers: Headers.build((final mh) => mh.contentLength = 99),
        ),
      );

      final reply = await raw(
        'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, rest) = split(reply);
      expect(first.toLowerCase(), contains('content-length: 2'));
      expect(first.toLowerCase(), isNot(contains('content-length: 99')));
      expect(rest, 'ok');
    });

    test('when a request asks to close the connection, '
        'then the response says Connection: close once and the connection '
        'closes', () async {
      await serve(ok);

      // The read ends when the server closes, so a reply at all is the
      // closed connection.
      final reply = await raw(
        'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, rest) = split(reply);
      expect(first, startsWith('HTTP/1.1 200'));
      expect('connection: close'.allMatches(first.toLowerCase()), hasLength(1));
      expect(rest, 'ok');
    });

    test('when a request keeps the connection alive, '
        'then the response carries no Connection: close', () async {
      await serve(ok);

      final reply = await raw(
        'GET / HTTP/1.1\r\nHost: x\r\n\r\n'
        'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
      );

      final (first, _) = split(reply);
      expect(first, startsWith('HTTP/1.1 200'));
      expect(first.toLowerCase(), isNot(contains('connection: close')));
    });

    test('when an HTTP/1.0 client gets a body of unknown length, '
        'then it is not chunked and the connection closes after it', () async {
      await serve(
        (final req) => Response.ok(
          body: Body.fromDataStream(
            Stream.fromIterable([
              Uint8List.fromList(utf8.encode('ab')),
              Uint8List.fromList(utf8.encode('cd')),
            ]),
          ),
        ),
      );

      final reply = await raw('GET / HTTP/1.0\r\nHost: x\r\n\r\n');

      final (first, rest) = split(reply);
      expect(first.toLowerCase(), isNot(contains('transfer-encoding')));
      expect(first.toLowerCase(), isNot(contains('content-length')));
      expect(rest, 'abcd');
    });
  });
}
