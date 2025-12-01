import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as parser;
import 'package:relic/relic.dart';
import 'package:relic/src/headers/codecs/common_types_codecs.dart';
import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart';

import 'headers/headers_test_utils.dart';
import 'ssl/ssl_certs.dart';
import 'util/fake_adapter/fake_adapter_utils.dart';
import 'util/test_util.dart';

void main() {
  group('Given a server (harness)', () {
    late TestHarness harness;

    setUp(() async {
      harness = await createHarness();
    });

    tearDown(() => harness.close());

    test('sync handler returns a value to the client', () async {
      await harness.mount(syncHandler);

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'Hello from /');
    });

    test('async handler returns a value to the client', () async {
      await harness.mount(asyncHandler);

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'Hello from /');
    });

    test('thrown error leads to a 500', () async {
      await harness.mount((final request) {
        throw UnsupportedError('test');
      });

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.body, 'Internal Server Error');
    });

    test('async error leads to a 500', () async {
      await harness.mount((final request) {
        return Future.error('test');
      });

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.body, 'Internal Server Error');
    });

    test('Request is populated correctly', () async {
      late Uri expectedUri;

      await harness.mount((final req) {
        expect(req.method, Method.get);
        expect(req.url.path, '/foo/bar');
        expect(req.url.pathSegments, ['foo', 'bar']);
        expect(req.url.query, 'qs=value');

        return syncHandler(req);
      });

      expectedUri = harness
          .urlFor('/foo/bar')
          .replace(queryParameters: {'qs': 'value'});
      final response = await harness.client.get(expectedUri);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'Hello from /foo/bar');
    });

    test('Request can handle colon in first path segment', () async {
      await harness.mount(syncHandler);

      final response = await harness.client.get(harness.urlFor('/user:42'));
      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'Hello from /user:42');
    });

    test('custom response headers are received by the client', () async {
      await harness.mount(
        createSyncHandler(
          body: Body.fromString('Hello from /'),
          headers: Headers.fromMap({
            'test-header': ['test-value'],
            'test-list': ['a', 'b', 'c'],
          }),
        ),
      );

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['test-header'], 'test-value');
      expect(response.body, 'Hello from /');
    });

    test('custom status code is received by the client', () async {
      await harness.mount(
        createSyncHandler(
          statusCode: 299,
          body: Body.fromString('Hello from /'),
        ),
      );

      final response = await harness.client.get(harness.url);
      expect(response.statusCode, 299);
      expect(response.body, 'Hello from /');
    });

    test('custom request headers are received by the handler', () async {
      const multi = HeaderAccessor<List<String>>(
        'multi-header',
        HeaderCodec(parseStringList, encodeStringList),
      );
      await harness.mount((final req) {
        expect(req.headers, containsPair('custom-header', ['client value']));

        // dart:io HttpServer splits multi-value headers into an array
        // validate that they are combined correctly
        expect(req.headers, containsPair('multi-header', ['foo,bar,baz']));

        expect(multi[req.headers].value, ['foo', 'bar', 'baz']);

        return syncHandler(req);
      });

      final request = http.Request(Method.get.value, harness.url);
      request.headers['custom-header'] = 'client value';
      request.headers['multi-header'] = 'foo,bar,baz';

      final response = await harness.client.send(request);
      expect(response.statusCode, HttpStatus.ok);
    });

    group('date header', () {
      test('is sent by default', () async {
        await harness.mount(syncHandler);

        // Update beforeRequest to be one second earlier. HTTP dates only have
        // second-level granularity and the request will likely take less than a
        // second.
        final beforeRequest = DateTime.now().subtract(
          const Duration(seconds: 1),
        );

        final response = await harness.client.get(harness.url);
        expect(response.headers, contains('date'));
        final responseDate = parser.parseHttpDate(response.headers['date']!);

        expect(responseDate.isAfter(beforeRequest), isTrue);
        expect(responseDate.isBefore(DateTime.now()), isTrue);
      });

      test('defers to header in response', () async {
        final date = DateTime.utc(1981, 6, 5);
        await harness.mount(
          createSyncHandler(
            body: Body.fromString('test'),
            headers: Headers.build((final mh) => mh.date = date),
          ),
        );

        final response = await harness.client.get(harness.url);
        expect(response.headers, contains('date'));
        final responseDate = parser.parseHttpDate(response.headers['date']!);
        expect(responseDate, date);
      });
    });

    group('X-Powered-By header', () {
      const poweredBy = 'x-powered-by';

      test('is not automatically set', () async {
        await harness.mount(syncHandler);

        final response = await harness.client.get(harness.url);
        expect(response.headers[poweredBy], isNull);
      });

      test('can be set manually in response headers', () async {
        await harness.mount(
          respondWith((final request) {
            return Response.ok(
              body: Body.fromString('test'),
              headers: Headers.build((final mh) => mh.xPoweredBy = 'myServer'),
            );
          }),
        );

        final response = await harness.client.get(harness.url);
        expect(response.headers, containsPair(poweredBy, 'myServer'));
      });

      test('preserves manually set header in response', () async {
        await harness.mount(
          createSyncHandler(
            headers: Headers.build((final mh) => mh.xPoweredBy = 'myServer'),
          ),
        );

        final response = await harness.client.get(harness.url);
        expect(response.headers, containsPair(poweredBy, 'myServer'));
      });
    });
  });

  // Tests requiring real network IO (raw sockets, hijacking, WebSocket, SSL, zones)
  group('Given a server (IO-only)', () {
    RelicServer? server;

    int serverPort() => server!.url.port;

    Future<void> scheduleServer(
      final Handler handler, {
      final SecurityContext? securityContext,
    }) async {
      assert(server == null);
      server = await testServe(handler, context: securityContext);
    }

    tearDown(() async {
      final s = server;
      if (s != null) {
        try {
          await s.close().timeout(const Duration(seconds: 5));
        } catch (e) {
          await s.close();
        } finally {
          server = null;
        }
      }
    });

    test('post with empty content', () async {
      await scheduleServer((final req) async {
        expect(req.mimeType, isNull);
        expect(req.encoding, isNull);
        expect(req.method, Method.post);
        expect(req.body.contentLength, isNull);

        final body = await req.readAsString();
        expect(body, '');
        return syncHandler(req);
      });

      final request = http.Request(
        Method.post.value,
        Uri.http('localhost:${serverPort()}', ''),
      );
      final response = await request.send();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.stream.bytesToString(), completion('Hello from /'));
    });

    test('post with request content', () async {
      await scheduleServer((final req) async {
        expect(req.mimeType?.primaryType, 'text');
        expect(req.mimeType?.subType, 'plain');
        expect(req.encoding, utf8);
        expect(req.method, Method.post);
        expect(req.body.contentLength, 9);

        final body = await req.readAsString();
        expect(body, 'test body');

        return syncHandler(req);
      });

      final request = http.Request(
        Method.post.value,
        Uri.http('localhost:${serverPort()}', ''),
      );
      request.body = 'test body';
      final response = await request.send();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.stream.bytesToString(), completion('Hello from /'));
    });

    test(
      'Given a response with a chunked transfer encoding header and an empty body '
      'when applying headers '
      'then the chunked transfer encoding header is removed from the response',
      () async {
        await scheduleServer(
          createSyncHandler(
            body: Body.empty(),
            headers: Headers.build(
              (final mh) =>
                  mh.transferEncoding = TransferEncodingHeader.encodings([
                    TransferEncoding.chunked,
                  ]),
            ),
          ),
        );

        final response = await http.get(
          Uri.http('localhost:${serverPort()}', ''),
        );
        expect(response.body, isEmpty);
        expect(response.headers['transfer-encoding'], isNull);
      },
    );

    test('supports request hijacking', () async {
      await scheduleServer((final req) {
        expect(req.method, Method.post);

        return Hijack(
          expectAsync1((final channel) {
            expect(channel.stream.first, completion(equals('Hello'.codeUnits)));

            channel.sink.add(
              'HTTP/1.1 404 Not Found\r\n'
                      'date: Mon, 23 May 2005 22:38:34 GMT\r\n'
                      'Content-Length: 13\r\n'
                      '\r\n'
                      'Hello, world!'
                  .codeUnits,
            );
            channel.sink.close();
          }),
        );
      });

      final request = http.Request(
        Method.post.value,
        Uri.http('localhost:${serverPort()}', ''),
      );
      request.body = 'Hello';

      final response = await request.send();
      expect(response.statusCode, HttpStatus.notFound);
      expect(response.headers['date'], 'Mon, 23 May 2005 22:38:34 GMT');
      expect(
        response.stream.bytesToString(),
        completion(equals('Hello, world!')),
      );
    });

    test('supports web socket connections', () async {
      await scheduleServer((final req) {
        return WebSocketUpgrade(
          expectAsync1((final serverSocket) async {
            await for (final e in serverSocket.events) {
              expect(e, TextDataReceived('Hello'));
              serverSocket.sendText('Hello, world!');
              await serverSocket.close();
            }
          }),
        );
      });

      final ws = await WebSocket.connect(
        Uri.parse('ws://localhost:${serverPort()}'),
      );
      ws.sendText('Hello');
      expect(ws.events.first, completion(TextDataReceived('Hello, world!')));
    });

    test('passes asynchronous exceptions to the parent error zone', () async {
      await runZonedGuarded(
        () async {
          final s = await testServe((final req) {
            Future(() => throw StateError('oh no'));
            return syncHandler(req);
          });

          final response = await http.get(s.url);
          expect(response.statusCode, HttpStatus.ok);
          expect(response.body, 'Hello from /');
          await s.close();
        },
        expectAsync2((final error, final stack) {
          expect(error, isOhNoStateError);
        }),
      );
    });

    test(
      "doesn't pass asynchronous exceptions to the root error zone",
      () async {
        final response = await Zone.root.run(() async {
          final s = await testServe((final request) {
            Future(() => throw StateError('oh no'));
            return syncHandler(request);
          });

          try {
            return await http.get(s.url);
          } finally {
            await s.close();
          }
        });

        expect(response.statusCode, HttpStatus.ok);
        expect(response.body, 'Hello from /');
      },
    );

    test('a bad HTTP host request results in a 400 response', () async {
      await scheduleServer(syncHandler);

      final socket = await Socket.connect('localhost', serverPort());

      try {
        socket.write('GET / HTTP/1.1\r\n');
        socket.write('Host: ^^super bad !@#host\r\n');
        socket.write('\r\n');
      } finally {
        await socket.close();
      }

      expect(await utf8.decodeStream(socket), contains('400 Bad Request'));
    });

    test('a bad HTTP URL request results in a 400 response', () async {
      await scheduleServer(syncHandler);
      final socket = await Socket.connect('localhost', serverPort());

      try {
        socket.write('GET /#/ HTTP/1.1\r\n');
        socket.write('Host: localhost\r\n');
        socket.write('\r\n');
      } finally {
        await socket.close();
      }

      expect(await utf8.decodeStream(socket), contains('400 Bad Request'));
    });

    test(
      'respects the "buffer_output" context parameter',
      () async {
        final controller = StreamController<String>();
        await scheduleServer(
          respondWith((final request) {
            controller.add('Hello, ');

            return Response.ok(
              body: Body.fromDataStream(
                utf8.encoder
                    .bind(controller.stream)
                    .map((final list) => Uint8List.fromList(list)),
              ),
            );
          }),
        );

        final request = http.Request(
          Method.get.value,
          Uri.http('localhost:${serverPort()}', ''),
        );

        final response = await request.send();
        final stream = StreamQueue(utf8.decoder.bind(response.stream));

        var data = await stream.next;
        expect(data, equals('Hello, '));
        controller.add('world!');

        data = await stream.next;
        expect(data, equals('world!'));
        await controller.close();
        expect(stream.hasNext, completion(isFalse));
      },
      skip: 'TODO: Find another way to probagate buffer_output',
    );

    group('ssl tests', () {
      final securityContext =
          SecurityContext()
            ..setTrustedCertificatesBytes(certChainBytes)
            ..useCertificateChainBytes(certChainBytes)
            ..usePrivateKeyBytes(certKeyBytes, password: 'dartdart');

      final sslClient = HttpClient(context: securityContext);

      Future<HttpClientRequest> scheduleSecureGet() =>
          sslClient.getUrl(server!.url.replace(scheme: 'https'));

      test('secure sync handler returns a value to the client', () async {
        await scheduleServer(syncHandler, securityContext: securityContext);

        final req = await scheduleSecureGet();

        final response = await req.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          await response.cast<List<int>>().transform(utf8.decoder).single,
          'Hello from /',
        );
      });

      test('secure async handler returns a value to the client', () async {
        await scheduleServer(asyncHandler, securityContext: securityContext);

        final req = await scheduleSecureGet();
        final response = await req.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          await response.cast<List<int>>().transform(utf8.decoder).single,
          'Hello from /',
        );
      });
    });
  });
}
