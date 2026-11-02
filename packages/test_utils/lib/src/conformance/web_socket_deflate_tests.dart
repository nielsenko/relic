import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart'
    show TextDataReceived, BinaryDataReceived;

import 'conformance.dart';

void webSocketDeflateTests(AdapterConformance conformance) {
  group('Given permessage-deflate on a WebSocket upgrade', () {
    _webSocketDeflateTests(conformance);
  }, skip: conformance.skipWebSocketDeflate);
}

void _webSocketDeflateTests(AdapterConformance conformance) {
  late RelicServer server;
  late Completer<RelicWebSocket> upgraded;

  Future<void> serve({WebSocketCompression? compression}) async {
    upgraded = Completer<RelicWebSocket>();
    server = await conformance.serve(
      (_) => WebSocketUpgrade(upgraded.complete, compression: compression),
    );
  }

  tearDown(() => server.close());

  /// The `Sec-WebSocket-Extensions` the server answers [offer] with, or
  /// null when it leaves the extension out.
  Future<String?> accepted({
    String offer = 'permessage-deflate; client_max_window_bits',
  }) async {
    final client = io.HttpClient();
    try {
      final request = await client.openUrl(
        'GET',
        Uri.parse('http://localhost:${server.url.port}/'),
      );
      request.headers
        ..set('connection', 'Upgrade')
        ..set('upgrade', 'websocket')
        ..set('sec-websocket-version', '13')
        ..set('sec-websocket-key', base64.encode(List.generate(16, (i) => i)))
        ..set('sec-websocket-extensions', offer);
      final response = await request.close();
      expect(response.statusCode, 101);
      final value = response.headers.value('sec-websocket-extensions');
      (await response.detachSocket()).destroy();
      return value;
    } finally {
      client.close(force: true);
    }
  }

  test('when the upgrade asks for it, '
      'then the handshake accepts the client offer', () async {
    await serve(compression: WebSocketCompression.defaults);

    expect(await accepted(), startsWith('permessage-deflate'));
  });

  test('when the client offers no context takeover and the upgrade wants it, '
      'then the handshake says so', () async {
    await serve(
      compression: const WebSocketCompression(
        serverNoContextTakeover: true,
        clientNoContextTakeover: true,
      ),
    );

    // dart:io agrees to no context takeover only when the client offers
    // it, so the offer here names both.
    final value = (await accepted(
      offer:
          'permessage-deflate; server_no_context_takeover; '
          'client_no_context_takeover',
    ))!;
    expect(value, contains('server_no_context_takeover'));
    expect(value, contains('client_no_context_takeover'));
  });

  test('when the upgrade does not ask for it, '
      'then the handshake leaves the extension out', () async {
    await serve();

    expect(await accepted(), isNull);
  });

  test('when a dart:io client offers it, '
      'then text and binary messages round trip both ways', () async {
    await serve(compression: const WebSocketCompression(threshold: 0));
    final client = await io.WebSocket.connect(
      'ws://localhost:${server.url.port}',
    );
    final socket = await upgraded.future;
    final big = Uint8List.fromList(
      List.generate(200000, (i) => (i * 13) & 0xff),
    );

    client.add('tick');
    client.add(big);
    client.add('tick' * 10000);
    final events = StreamIterator(socket.events);
    expect(await events.moveNext(), isTrue);
    expect(events.current, TextDataReceived('tick'));
    expect(await events.moveNext(), isTrue);
    expect(events.current, BinaryDataReceived(big));
    expect(await events.moveNext(), isTrue);
    expect(events.current, TextDataReceived('tick' * 10000));

    socket.sendText('tock');
    socket.sendBytes(big);
    socket.sendText('tock' * 10000);
    final back = StreamIterator(client);
    expect(await back.moveNext(), isTrue);
    expect(back.current, 'tock');
    expect(await back.moveNext(), isTrue);
    expect(back.current, big);
    expect(await back.moveNext(), isTrue);
    expect(back.current, 'tock' * 10000);
    await client.close();
    await socket.done;
  });

  test('when the windows are small and no context carries over, '
      'then messages still round trip both ways', () async {
    await serve(
      compression: const WebSocketCompression(
        serverMaxWindowBits: 9,
        clientMaxWindowBits: 9,
        serverNoContextTakeover: true,
        clientNoContextTakeover: true,
        threshold: 0,
      ),
    );
    final client = await io.WebSocket.connect(
      'ws://localhost:${server.url.port}',
    );
    final socket = await upgraded.future;

    final events = StreamIterator(socket.events);
    final back = StreamIterator(client);
    for (var i = 0; i < 5; i++) {
      final text = 'round $i ' * 1000;
      client.add(text);
      expect(await events.moveNext(), isTrue);
      expect(events.current, TextDataReceived(text));
      socket.sendText(text);
      expect(await back.moveNext(), isTrue);
      expect(back.current, text);
    }
    await client.close();
    await socket.done;
  });

  test('when a client connects with compression off, '
      'then messages round trip as before', () async {
    await serve(compression: WebSocketCompression.defaults);
    final client = await io.WebSocket.connect(
      'ws://localhost:${server.url.port}',
      compression: io.CompressionOptions.compressionOff,
    );
    final socket = await upgraded.future;

    client.add('tick' * 1000);
    expect(await socket.events.first, TextDataReceived('tick' * 1000));
    socket.sendText('tock' * 1000);
    expect(await client.first, 'tock' * 1000);
    await client.close();
    await socket.done;
  });
}
