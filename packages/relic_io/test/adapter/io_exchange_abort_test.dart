import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic_core/relic_core.dart';
import 'package:relic_io/relic_io.dart';
import 'package:test/test.dart';

/// A response whose framing does not parse, so [AdapterExchange.respond]
/// fails before anything is written.
final _unwritable = Response.ok(
  headers: Headers.build((final mh) => mh['connection'] = ['close;x']),
);

void main() {
  late IOAdapter adapter;

  setUp(() async {
    adapter = await IOAdapter.bind(InternetAddress.loopbackIPv4);
  });

  tearDown(() => adapter.close(force: true));

  Future<String> get() async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      adapter.listeners.first.port,
    );
    socket.write(
      'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
    );
    await socket.flush();
    final reply = await utf8
        .decodeStream(socket)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('The connection was left open'),
        );
    socket.destroy();
    return reply;
  }

  test('Given a sink that aborts after a failed respond, '
      'when a request is made, '
      'then the connection is closed without a response', () async {
    adapter.start((final exchange) async {
      try {
        await exchange.respond(_unwritable);
      } catch (_) {
        exchange.abort();
      }
    });

    final reply = await get();

    expect(reply, isEmpty);
  });

  test('Given a sink that responds again after a failed respond, '
      'when a request is made, '
      'then the second response reaches the client', () async {
    adapter.start((final exchange) async {
      try {
        await exchange.respond(_unwritable);
      } catch (_) {
        await exchange.respond(Response.internalServerError());
      }
    });

    final reply = await get();

    expect(reply, startsWith('HTTP/1.1 500'));
  });

  test('Given a sink that aborts after a failed respond, '
      'when a request is made, '
      'then done reports the abort', () async {
    final ends = Completer<ExchangeEnd>();
    adapter.start((final exchange) async {
      try {
        await exchange.respond(_unwritable);
      } catch (_) {
        exchange.abort();
      }
      ends.complete(await exchange.done);
    });

    await get();

    expect(await ends.future, ExchangeEnd.aborted);
  });
}
