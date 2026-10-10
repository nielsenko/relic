import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import 'native_test_helpers.dart';

void main() {
  late RelicServer server;

  test('Given a handler that closes its own server forcefully, '
      'when a request reaches it, '
      'then the close completes and the port is released', () async {
    final closed = Completer<void>();
    server = await serveNative((final req) {
      closed.complete(server.close(force: true));
      return Response.ok(body: Body.fromString('bye'));
    });
    final port = server.port;

    try {
      await http.get(Uri.http('127.0.0.1:$port'));
    } on http.ClientException {
      // The connection is dropped with the server. Either outcome is fine.
    }

    await expectLater(
      closed.future.timeout(const Duration(seconds: 5)),
      completes,
    );
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
      reason: 'The listener must be gone after a forced close',
    );
  });

  test('Given a handler that closes its own server gracefully, '
      'when a request reaches it, '
      'then the response goes out and the close completes', () async {
    final closed = Completer<void>();
    server = await serveNative((final req) {
      closed.complete(server.close());
      return Response.ok(body: Body.fromString('bye'));
    });

    final response = await http.get(Uri.http('127.0.0.1:${server.port}'));

    expect(response.body, 'bye');
    await expectLater(
      closed.future.timeout(const Duration(seconds: 5)),
      completes,
    );
  });
}
