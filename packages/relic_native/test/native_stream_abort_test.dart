import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:relic_core/relic_core.dart';
import 'package:relic_native/relic_native.dart';
import 'package:test/test.dart';

/// Chunks without end, each far above the inline limit of the adapter, so
/// the response is streamed and the peer's buffer fills.
Stream<Uint8List> _endless() async* {
  final chunk = Uint8List(1 << 16);
  while (true) {
    yield chunk;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late NativeAdapter adapter;

  setUp(() async {
    adapter = await NativeAdapter.bind(
      InternetAddress.loopbackIPv4,
      maxInlineBody: 1024,
    );
  });

  tearDown(() => adapter.close(force: true));

  Future<Socket> request() async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      adapter.listeners.first.port,
    );
    socket.write('GET / HTTP/1.1\r\nHost: x\r\n\r\n');
    await socket.flush();
    return socket;
  }

  test('Given a streamed response, '
      'when the peer disconnects before it ends, '
      'then respond fails instead of staying pending', () async {
    final responded = Completer<Object>();
    adapter.start((final exchange) async {
      try {
        await exchange.respond(
          Response.ok(body: Body.fromDataStream(_endless())),
        );
        responded.complete('completed');
      } catch (e) {
        responded.complete(e);
      }
    });

    final socket = await request();
    await socket.first;
    socket.destroy();

    expect(
      await responded.future.timeout(const Duration(seconds: 5)),
      isA<SocketException>(),
    );
  });

  test('Given a streamed response, '
      'when the exchange is aborted during it, '
      'then respond fails and done reports the abort', () async {
    final responded = Completer<Object>();
    late AdapterExchange current;
    adapter.start((final exchange) async {
      current = exchange;
      try {
        await exchange.respond(
          Response.ok(body: Body.fromDataStream(_endless())),
        );
        responded.complete('completed');
      } catch (e) {
        responded.complete(e);
      }
    });

    final socket = await request();
    await socket.first;
    current.abort();

    expect(
      await responded.future.timeout(const Duration(seconds: 5)),
      isA<SocketException>(),
    );
    expect(await current.done, ExchangeEnd.aborted);
    socket.destroy();
  });
}
