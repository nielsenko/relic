import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import 'native_test_helpers.dart';

const _inlineLimit = 64 * 1024;

/// A body too big for the inline limit of the test server.
const _bigLength = 3 * 1024 * 1024;

Uint8List _pattern(final int length) =>
    Uint8List.fromList(List.generate(length, (final i) => i & 0xff));

/// [length] bytes of the pattern in [chunkSize] pieces, with a yield
/// between pieces so the producer never runs ahead of the event loop.
Stream<Uint8List> _patternStream(final int length, final int chunkSize) async* {
  for (var offset = 0; offset < length; offset += chunkSize) {
    final end = offset + chunkSize > length ? length : offset + chunkSize;
    yield Uint8List.fromList(
      List.generate(end - offset, (final i) => (offset + i) & 0xff),
    );
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late RelicServer server;
  late Uri url;

  tearDown(() => server.close(force: true));

  group('Given a streamed response', () {
    test('when its length is unknown, '
        'then the client receives it chunked and complete', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(
          body: Body.fromDataStream(_patternStream(_bigLength, 17 * 1024)),
        ),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.get(url);

      expect(response.headers['content-length'], isNull);
      expect(response.bodyBytes, _pattern(_bigLength));
    });

    test('when its length is known, '
        'then the client receives it with a Content-Length', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(
          body: Body.fromDataStream(
            _patternStream(_bigLength, 64 * 1024),
            contentLength: _bigLength,
          ),
        ),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.get(url);

      expect(response.headers['content-length'], '$_bigLength');
      expect(response.bodyBytes, _pattern(_bigLength));
    });

    test('when the body stream fails after the head went out, '
        'then the connection drops and no 500 is sent', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(
          body: Body.fromDataStream(() async* {
            yield Uint8List.fromList([1, 2, 3]);
            await Future<void>.delayed(const Duration(milliseconds: 50));
            throw StateError('the source broke');
          }()),
        ),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      await expectLater(http.get(url), throwsA(isA<http.ClientException>()));
    });

    test('when its body was already read, '
        'then the client gets a 500 and not a hanging 200', () async {
      server = await serveNative(maxInlineBody: _inlineLimit, (final req) {
        final body = Body.fromDataStream(_patternStream(1024, 256));
        body.read();
        return Response.ok(body: body);
      });
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.get(url).timeout(const Duration(seconds: 5));

      expect(response.statusCode, 500);
    });

    test('when a HEAD is answered with a streamed body, '
        'then only the head goes out', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(
          body: Body.fromDataStream(
            _patternStream(_bigLength, 64 * 1024),
            contentLength: _bigLength,
          ),
        ),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.head(url);

      expect(response.statusCode, 200);
      expect(response.headers['content-length'], '$_bigLength');
      expect(response.bodyBytes, isEmpty);
    });

    test(
      'when the peer resets mid-body, '
      'then the body stream is cancelled and the next request is served',
      () async {
        final cancelled = Completer<void>();
        server = await serveNative(maxInlineBody: _inlineLimit, (final req) {
          if (req.url.path != '/endless') {
            return Response.ok(body: Body.fromString('ok'));
          }
          late final StreamController<Uint8List> source;
          late final Timer pump;
          source = StreamController<Uint8List>(
            onListen: () {
              pump = Timer.periodic(const Duration(milliseconds: 5), (_) {
                if (!source.isPaused) source.add(Uint8List(64 * 1024));
              });
            },
            onCancel: () {
              pump.cancel();
              cancelled.complete();
            },
          );
          return Response.ok(body: Body.fromDataStream(source.stream));
        });
        url = Uri.http('127.0.0.1:${server.port}');

        final socket = await Socket.connect('127.0.0.1', server.port);
        socket.write('GET /endless HTTP/1.1\r\nHost: x\r\n\r\n');
        await socket.flush();
        await socket.first;
        socket.destroy();

        await expectLater(
          cancelled.future.timeout(const Duration(seconds: 5)),
          completes,
        );
        final next = await http.get(url).timeout(const Duration(seconds: 5));
        expect(next.body, 'ok');
      },
    );

    test('when the peer resets while a buffered body is being written, '
        'then the next request is served', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(body: Body.fromBytes(_pattern(8 << 20))),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
      await socket.flush();
      await socket.first;
      socket.destroy();

      final next = await http.get(url);
      expect(next.bodyBytes.length, 8 << 20);
    });

    test('when the handler keeps the connection alive, '
        'then a second request on it is served', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(
          body: Body.fromDataStream(_patternStream(100 * 1024, 7 * 1024)),
        ),
      );
      url = Uri.http('127.0.0.1:${server.port}');
      final client = http.Client();
      addTearDown(client.close);

      final first = await client.get(url);
      final second = await client.get(url);

      expect(first.bodyBytes, _pattern(100 * 1024));
      expect(second.bodyBytes, _pattern(100 * 1024));
    });
  });

  group('Given a streamed request body', () {
    test('when it is larger than the inline limit, '
        'then the handler reads all of it', () async {
      server = await serveNative(maxInlineBody: _inlineLimit, (
        final req,
      ) async {
        expect(req.body.contentLength, _bigLength);
        final received = await req.body.readAll();
        expect(received, _pattern(_bigLength));
        return Response.ok(body: Body.fromString('${received.length}'));
      });
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.post(url, body: _pattern(_bigLength));

      expect(response.body, '$_bigLength');
    });

    test('when it is chunked, then the handler reads all of it', () async {
      server = await serveNative(maxInlineBody: _inlineLimit, (
        final req,
      ) async {
        expect(req.body.contentLength, isNull);
        final received = await req.readAsString();
        return Response.ok(body: Body.fromString(received));
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write(
        'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n'
        'Connection: close\r\n\r\n'
        '5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n',
      );
      await socket.flush();
      final reply = await utf8.decodeStream(socket);

      expect(reply, endsWith('hello world'));
    });

    test('when the handler answers before reading it, '
        'then the response arrives', () async {
      server = await serveNative(
        maxInlineBody: _inlineLimit,
        (final req) => Response.ok(body: Body.fromString('early')),
      );
      url = Uri.http('127.0.0.1:${server.port}');

      final response = await http.post(url, body: _pattern(_bigLength));

      expect(response.body, 'early');
      expect(response.headers['connection'], anyOf(isNull, 'close'));
    });

    test('when the client stops sending mid-body, '
        'then the handler sees the body fail', () async {
      final failed = Completer<Object>();
      server = await serveNative(maxInlineBody: _inlineLimit, (
        final req,
      ) async {
        try {
          await req.body.readAll();
          return Response.ok(body: Body.fromString('complete'));
        } catch (e) {
          failed.complete(e);
          return Response.badRequest();
        }
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write(
        'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: ${_bigLength}\r\n\r\n',
      );
      socket.add(_pattern(1000));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.destroy();

      await expectLater(
        failed.future.timeout(const Duration(seconds: 5)),
        completion(isA<Object>()),
      );
    });
  });
}
