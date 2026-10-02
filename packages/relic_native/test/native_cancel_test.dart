import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import 'native_test_helpers.dart';

void main() {
  late RelicServer server;

  tearDown(() => server.close(force: true));

  test('Given a handler waiting on cancelled, when the peer hangs up, '
      'then cancelled completes while the handler still runs', () async {
    final sawCancel = Completer<void>();
    final release = Completer<void>();
    server = await serveNative((final req) async {
      unawaited(req.cancelled.then((_) => sawCancel.complete()));
      await release.future;
      return Response.ok();
    });

    final socket = await Socket.connect('127.0.0.1', server.port);
    socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    socket.destroy();

    await expectLater(
      sawCancel.future.timeout(const Duration(seconds: 3)),
      completes,
    );
    release.complete();
  });

  test('Given a handler waiting on cancelled, when the peer stays, '
      'then cancelled does not complete and the response arrives', () async {
    var cancelledFired = false;
    server = await serveNative((final req) async {
      unawaited(req.cancelled.then((_) => cancelledFired = true));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return Response.ok(body: Body.fromString('done'));
    });

    final response = await http.get(Uri.http('127.0.0.1:${server.port}'));

    expect(response.body, 'done');
    expect(cancelledFired, isFalse);
  });

  test('Given a keep-alive connection that was answered, '
      'when the peer closes it, then the server lets it go', () async {
    server = await serveNative(
      (final req) => Response.ok(body: Body.fromString('ok')),
    );

    final socket = await Socket.connect('127.0.0.1', server.port);
    socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
    await socket.flush();
    await socket.first;
    socket.destroy();

    var info = await server.connectionsInfo();
    final deadline = Stopwatch()..start();
    while (info.idle + info.active > 0 &&
        deadline.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      info = await server.connectionsInfo();
    }
    expect(info.idle + info.active, 0);
  });

  test(
    'Given a handler that never reads cancelled, '
    'when the peer hangs up, then the server serves the next request',
    () async {
      server = await serveNative((final req) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return Response.ok(body: Body.fromString('ok'));
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
      await socket.flush();
      socket.destroy();

      final response = await http.get(Uri.http('127.0.0.1:${server.port}'));
      expect(response.body, 'ok');
    },
  );
}
