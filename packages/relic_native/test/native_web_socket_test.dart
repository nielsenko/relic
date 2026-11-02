import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show WebSocket;
import 'dart:typed_data';

import 'package:relic_core/adapter.dart';
import 'package:relic_core/relic_core.dart';
import 'package:relic_native/relic_native.dart';
import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart';

import 'native_test_helpers.dart';

/// A frame off the wire from the server, which never masks.
typedef _Frame = ({int opcode, bool fin, bool rsv1, Uint8List payload});

/// How long the native side waits for the peer's close frame after
/// sending its own.
const _closeWait = Duration(seconds: 2);

void main() {
  late RelicServer server;
  late Completer<RelicWebSocket> upgraded;

  Future<void> serve({
    int maxWebSocketMessage = FramedWebSocket.defaultMaxMessageSize,
    WebSocketCompression? compression,
  }) async {
    upgraded = Completer<RelicWebSocket>();
    server = await serveNative(
      (_) => WebSocketUpgrade(upgraded.complete, compression: compression),
      options: NativeOptions(maxWebSocketMessage: maxWebSocketMessage),
    );
  }

  tearDown(() => server.close(force: true));

  test(
    'Given an upgraded connection, when the client sends masked text, '
    'then the handler receives it and answers in an unmasked frame',
    () async {
      await serve();
      final client = await _Client.connect(server.port);
      final socket = await upgraded.future;

      client.send(1, utf8.encode('tick'));
      expect(await socket.events.first, TextDataReceived('tick'));
      socket.sendText('tock');

      final frame = (await client.next())!;
      expect(frame.opcode, 1);
      expect(frame.fin, isTrue);
      expect(utf8.decode(frame.payload), 'tock');
      client.destroy();
    },
  );

  test('Given an upgraded connection, '
      'when the client sends an empty text message, '
      'then the handler receives an empty string', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(1, const []);

    expect(await socket.events.first, TextDataReceived(''));
    client.destroy();
  });

  test('Given an upgraded connection, '
      'when a message arrives in fragments with a ping between them, '
      'then the pong comes first and the message comes whole', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(1, utf8.encode('hello '), fin: false);
    client.send(9, utf8.encode('p'));
    client.send(0, utf8.encode('world'));

    final pong = (await client.next())!;
    expect(pong.opcode, 10);
    expect(utf8.decode(pong.payload), 'p');
    expect(await socket.events.first, TextDataReceived('hello world'));
    client.destroy();
  });

  test('Given an upgraded connection, '
      'when a 70000 byte binary message is echoed, '
      'then it comes back intact', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;
    socket.events.listen((event) {
      if (event is BinaryDataReceived) socket.sendBytes(event.data);
    });
    final message = Uint8List.fromList(
      List.generate(70000, (i) => (i * 7) & 0xff),
    );

    client.send(2, message);

    final echo = (await client.next())!;
    expect(echo.opcode, 2);
    expect(echo.payload, message);
    client.destroy();
  });

  test(
    'Given an upgraded connection, '
    'when the client sends an unmasked frame, '
    'then the handler hears a 1002 close and the connection ends without waiting for the peer',
    () async {
      await serve();
      final client = await _Client.connect(server.port);
      final socket = await upgraded.future;
      final clock = Stopwatch()..start();

      client.send(1, const [0x41], masked: false);

      await expectLater(
        socket.events,
        emitsInOrder([
          emitsError(isA<WebSocketException>()),
          CloseReceived(1002, 'A client frame must be masked'),
          emitsDone,
        ]),
      );
      final close = (await client.next())!;
      expect(close.opcode, 8);
      expect(close.payload.sublist(0, 2), [0x03, 0xea]);
      expect(await client.next(), isNull);
      await socket.done;
      expect(clock.elapsed, lessThan(_closeWait));
    },
  );

  test('Given an upgraded connection, '
      'when the client sends text that is not UTF-8, '
      'then the handler hears a 1007 close', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(1, const [0xff, 0xfe]);

    await expectLater(
      socket.events,
      emitsInOrder([
        emitsError(isA<WebSocketException>()),
        CloseReceived(1007, 'Text is not valid UTF-8'),
        emitsDone,
      ]),
    );
    final close = (await client.next())!;
    expect(close.payload.sublist(0, 2), [0x03, 0xef]);
  });

  test('Given a message limit of 16 bytes, when fragments add up past it, '
      'then the handler hears a 1009 close', () async {
    await serve(maxWebSocketMessage: 16);
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(2, List.filled(10, 1), fin: false);
    client.send(0, List.filled(10, 2));

    await expectLater(
      socket.events,
      emitsInOrder([
        emitsError(isA<WebSocketException>()),
        CloseReceived(1009, 'Message too big'),
        emitsDone,
      ]),
    );
    final close = (await client.next())!;
    expect(close.payload.sublist(0, 2), [0x03, 0xf1]);
  });

  test('Given an upgraded connection, '
      'when the client closes with 4000 and a reason, '
      'then the handler sees both and the client gets its code back', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(8, [0x0f, 0xa0, ...utf8.encode('bye')]);

    await expectLater(
      socket.events,
      emitsInOrder([CloseReceived(4000, 'bye'), emitsDone]),
    );
    final close = (await client.next())!;
    expect(close.opcode, 8);
    expect(close.payload, [0x0f, 0xa0]);
    expect(await client.next(), isNull);
    await socket.done;
  });

  test('Given an upgraded connection, '
      'when the client closes with a code it may not send, '
      'then the handler hears a 1002 close', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.send(8, const [0x03, 0xed]); // 1005

    await expectLater(
      socket.events,
      emitsInOrder([
        emitsError(isA<WebSocketException>()),
        CloseReceived(1002, 'Close code 1005'),
        emitsDone,
      ]),
    );
  });

  test('Given an upgraded connection, '
      'when the client drops the connection, '
      'then the handler sees 1006 and done completes', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    client.destroy();

    await expectLater(
      socket.events,
      emitsInOrder([CloseReceived(1006, ''), emitsDone]),
    );
    await socket.done;
  });

  test('Given a keep-alive connection whose first handler read cancelled, '
      'when the client upgrades on it and drops the connection, '
      'then the handler sees 1006', () async {
    upgraded = Completer<RelicWebSocket>();
    server = await serveNative((request) {
      if (request.url.path == '/plain') {
        unawaited(request.cancelled);
        return Response.ok();
      }
      return WebSocketUpgrade(upgraded.complete);
    });
    final client = await _Client.connect(server.port, reused: true);
    final socket = await upgraded.future;

    client.destroy();

    await expectLater(
      socket.events,
      emitsInOrder([CloseReceived(1006, ''), emitsDone]),
    );
  });

  test('Given an upgraded connection, '
      'when the handler sends 1000 messages in one go, '
      'then the client gets them all in order', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    for (var i = 0; i < 1000; i++) {
      socket.sendText('$i');
    }

    for (var i = 0; i < 1000; i++) {
      expect(utf8.decode((await client.next())!.payload), '$i');
    }
    client.destroy();
  });

  test('Given an upgraded connection whose handler echoes every message, '
      'when the client sends 200 messages, '
      'then it gets every echo in order', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;
    socket.events.listen((event) {
      if (event is TextDataReceived) socket.sendText(event.text);
    });

    for (var i = 0; i < 200; i++) {
      client.send(1, utf8.encode('$i'));
    }

    for (var i = 0; i < 200; i++) {
      expect(utf8.decode((await client.next())!.payload), '$i');
    }
    client.destroy();
  });

  test('Given an upgraded connection, '
      'when the handler closes with 1000 and the client answers, '
      'then the client got the frame and done completes at once', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;
    final clock = Stopwatch()..start();

    await socket.close(1000, 'done');

    final close = (await client.next())!;
    expect(close.opcode, 8);
    expect(close.payload, [0x03, 0xe8, ...utf8.encode('done')]);
    client.send(8, const [0x03, 0xe8]);
    await socket.done;
    expect(clock.elapsed, lessThan(_closeWait));
    expect(await client.next(), isNull);
  });

  test('Given an upgraded connection, '
      'when the handler closes and the client never answers, '
      'then done completes once the close wait is over', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;
    final clock = Stopwatch()..start();

    await socket.close();

    await socket.done;
    expect(clock.elapsed, greaterThan(_closeWait ~/ 2));
    expect(clock.elapsed, lessThan(_closeWait * 3));
    expect(await client.next(), isNotNull); // the close frame
    expect(await client.next(), isNull);
  });

  test('Given a ping interval, when the client never answers the pings, '
      'then the socket closes with 1001', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;

    socket.pingInterval = const Duration(milliseconds: 50);

    final ping = (await client.next())!;
    expect(ping.opcode, 9);
    await expectLater(
      socket.events,
      emitsInOrder([CloseReceived(1001, ''), emitsDone]),
    );
    final close = (await client.next())!;
    expect(close.opcode, 8);
    expect(close.payload.sublist(0, 2), [0x03, 0xe9]);
  });

  test('Given a ping interval, when the client answers every ping, '
      'then the socket stays open', () async {
    await serve();
    final client = await _Client.connect(server.port);
    final socket = await upgraded.future;
    // A pong must arrive within the interval, which a slow runner needs
    // more than 20 ms for.
    socket.pingInterval = const Duration(milliseconds: 100);

    for (var i = 0; i < 3; i++) {
      final ping = (await client.next())!;
      expect(ping.opcode, 9);
      client.send(10, ping.payload);
    }

    expect(socket.isClosed, isFalse);
    client.send(1, utf8.encode('still here'));
    expect(await socket.events.first, TextDataReceived('still here'));
    client.destroy();
  });

  test('Given an upgrade request with a chunked body, '
      'when the client sends text after the 101, '
      'then the handler receives the text as its first event', () async {
    await serve();
    final client = await _Client.connect(server.port, chunkedBody: 'hello');
    final socket = await upgraded.future;

    client.send(1, utf8.encode('tick'));

    expect(await socket.events.first, TextDataReceived('tick'));
    client.destroy();
  });

  group('Given permessage-deflate on the upgrade', () {
    test('when a dart:io client offers it, '
        'then messages both ways come through its own compressor', () async {
      await serve(compression: const WebSocketCompression(threshold: 0));
      final client = await io.WebSocket.connect(
        'ws://localhost:${server.port}',
      );
      final socket = await upgraded.future;

      final big = Uint8List.fromList(
        List.generate(100000, (i) => (i * 7) & 0xff),
      );
      client.add('tick');
      client.add(big);
      final events = StreamIterator(socket.events);
      expect(await events.moveNext(), isTrue);
      expect(events.current, TextDataReceived('tick'));
      expect(await events.moveNext(), isTrue);
      expect(events.current, BinaryDataReceived(big));

      socket.sendText('tock');
      socket.sendBytes(big);
      final back = StreamIterator(client);
      expect(await back.moveNext(), isTrue);
      expect(back.current, 'tock');
      expect(await back.moveNext(), isTrue);
      expect(back.current, big);
      await client.close();
    });

    test(
      'when the client sends a compressed message after the connection '
      'sat idle, '
      'then the handler gets it inflated in the context of the first',
      () async {
        await serve(compression: const WebSocketCompression(threshold: 0));
        final client = await io.WebSocket.connect(
          'ws://localhost:${server.port}',
        );
        final socket = await upgraded.future;
        final events = StreamIterator(socket.events);
        final text = 'the same words again ' * 100;

        client.add(text);
        expect(await events.moveNext(), isTrue);
        expect(events.current, TextDataReceived(text));
        // Long enough for the connection to give up its task. The client's
        // compressor keeps its window, so the next message refers to this one.
        await Future<void>.delayed(const Duration(seconds: 3));
        client.add(text);

        expect(await events.moveNext(), isTrue);
        expect(events.current, TextDataReceived(text));
        await client.close();
      },
    );

    test('when the client never offered it, '
        'then the handshake leaves it out and frames go as is', () async {
      await serve(compression: WebSocketCompression.defaults);
      final client = await _Client.connect(server.port);
      final socket = await upgraded.future;
      expect(client.head, isNot(contains('Sec-WebSocket-Extensions')));

      socket.sendText('x' * 1000);
      final frame = (await client.next())!;
      expect(frame.rsv1, isFalse);
      expect(frame.payload.length, 1000);
      client.destroy();
    });

    test('when the server sends a message under the threshold, '
        'then it goes as is, and one over it compressed with RSV1', () async {
      await serve(compression: const WebSocketCompression(threshold: 100));
      final client = await _Client.connect(
        server.port,
        extensions: 'permessage-deflate; client_max_window_bits',
      );
      final socket = await upgraded.future;
      expect(
        client.head,
        contains('Sec-WebSocket-Extensions: permessage-deflate\r\n'),
      );

      socket.sendText('short');
      final short = (await client.next())!;
      expect(short.rsv1, isFalse);
      expect(utf8.decode(short.payload), 'short');

      socket.sendText('x' * 1000);
      final long = (await client.next())!;
      expect(long.rsv1, isTrue);
      expect(long.payload.length, lessThan(100));
      client.destroy();
    });

    test('when the client sends a compressed message, '
        'then the handler gets it inflated', () async {
      await serve(compression: WebSocketCompression.defaults);
      final client = await _Client.connect(
        server.port,
        extensions: 'permessage-deflate',
      );
      final socket = await upgraded.future;

      // A finished raw deflate stream, which ends in a final block instead
      // of the sync-flush tail. The server takes either.
      final packed = ZLibEncoder(raw: true).convert(utf8.encode('y' * 5000));
      final events = StreamIterator(socket.events);
      for (var i = 0; i < 2; i++) {
        client.send(1, packed, rsv1: true);
        expect(await events.moveNext(), isTrue);
        expect(events.current, TextDataReceived('y' * 5000));
      }
      client.destroy();
    });

    test('when the client sends bytes that are no deflate stream, '
        'then the connection closes with 1007', () async {
      await serve(compression: WebSocketCompression.defaults);
      final client = await _Client.connect(
        server.port,
        extensions: 'permessage-deflate',
      );
      final socket = await upgraded.future;

      client.send(2, [0xff, 0xff, 0xff, 0xff], rsv1: true);
      final close = (await client.next())!;
      expect(close.opcode, 8);
      expect((close.payload[0] << 8) | close.payload[1], 1007);
      await expectLater(socket.events, emitsError(isA<WebSocketException>()));
      client.destroy();
    });

    test('when the client sets RSV1 on a continuation frame, '
        'then the connection closes with 1002', () async {
      await serve(compression: WebSocketCompression.defaults);
      final client = await _Client.connect(
        server.port,
        extensions: 'permessage-deflate',
      );
      await upgraded.future;

      client.send(1, [0], fin: false, rsv1: true);
      client.send(0, [0], rsv1: true);
      final close = (await client.next())!;
      expect(close.opcode, 8);
      expect((close.payload[0] << 8) | close.payload[1], 1002);
      client.destroy();
    });

    test('when a compressed message inflates past the limit, '
        'then the connection closes with 1009', () async {
      await serve(
        compression: WebSocketCompression.defaults,
        maxWebSocketMessage: 1000,
      );
      final client = await _Client.connect(
        server.port,
        extensions: 'permessage-deflate',
      );
      await upgraded.future;

      final packed = ZLibEncoder(raw: true).convert(Uint8List(100000));
      expect(packed.length, lessThan(1000));
      client.send(2, packed, rsv1: true);
      final close = (await client.next())!;
      expect(close.opcode, 8);
      expect((close.payload[0] << 8) | close.payload[1], 1009);
      client.destroy();
    });
  });
}

/// A client on a raw socket, past the opening handshake, that sends
/// masked frames and reads the server's back.
final class _Client {
  final Socket _socket;
  final StreamIterator<Uint8List> _chunks;
  Uint8List _buffer = Uint8List(0);

  /// The 101 response head.
  late final String head;

  _Client._(this._socket) : _chunks = StreamIterator(_socket);

  /// Upgrades a fresh connection, after one plain request on it when
  /// [reused] is set, offering [extensions] when there are any. The
  /// upgrade request carries [chunkedBody] when there is one.
  static Future<_Client> connect(
    int port, {
    bool reused = false,
    String? chunkedBody,
    String? extensions,
  }) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final client = _Client._(socket);
    if (reused) {
      socket.write('GET /plain HTTP/1.1\r\nHost: localhost\r\n\r\n');
      await socket.flush();
      expect(await client._head(), startsWith('HTTP/1.1 200 '));
    }
    socket.write(webSocketUpgradeFields);
    if (extensions != null) {
      socket.write('Sec-WebSocket-Extensions: $extensions\r\n');
    }
    socket.write(
      chunkedBody == null
          ? '\r\n'
          : 'Transfer-Encoding: chunked\r\n\r\n'
                '${chunkedBody.length.toRadixString(16)}\r\n$chunkedBody\r\n'
                '0\r\n\r\n',
    );
    await socket.flush();
    client.head = await client._head();
    expect(client.head, startsWith('HTTP/1.1 101 '));
    return client;
  }

  Future<bool> _more() async {
    if (!await _chunks.moveNext()) return false;
    _buffer =
        (BytesBuilder(copy: false)
              ..add(_buffer)
              ..add(_chunks.current))
            .takeBytes();
    return true;
  }

  Future<String> _head() async {
    while (true) {
      final text = latin1.decode(_buffer);
      final end = text.indexOf('\r\n\r\n');
      if (end >= 0) {
        _buffer = _buffer.sublist(end + 4);
        return text.substring(0, end + 4);
      }
      if (!await _more()) fail('The connection closed before the head');
    }
  }

  /// The next frame, or null once the server closed the connection.
  Future<_Frame?> next() async {
    while (true) {
      final frame = _parse();
      if (frame != null) return frame;
      if (!await _more()) return null;
    }
  }

  _Frame? _parse() {
    final b = _buffer;
    if (b.length < 2) return null;
    var length = b[1] & 0x7f;
    var offset = 2;
    if (length == 126) {
      if (b.length < 4) return null;
      length = (b[2] << 8) | b[3];
      offset = 4;
    } else if (length == 127) {
      if (b.length < 10) return null;
      length = 0;
      for (var i = 2; i < 10; i++) {
        length = (length << 8) | b[i];
      }
      offset = 10;
    }
    if (b.length < offset + length) return null;
    final frame = (
      opcode: b[0] & 0x0f,
      fin: b[0] & 0x80 != 0,
      rsv1: b[0] & 0x40 != 0,
      payload: Uint8List.sublistView(b, offset, offset + length),
    );
    _buffer = b.sublist(offset + length);
    return frame;
  }

  /// Sends a frame, masked as a client's must be unless [masked] is off,
  /// with RSV1 set when [rsv1] is.
  void send(
    int opcode,
    List<int> payload, {
    bool fin = true,
    bool masked = true,
    bool rsv1 = false,
  }) {
    const mask = [0x37, 0xfa, 0x21, 0x3d];
    final length = payload.length;
    final maskBit = masked ? 0x80 : 0;
    final frame = BytesBuilder(copy: false)
      ..addByte((fin ? 0x80 : 0) | (rsv1 ? 0x40 : 0) | opcode);
    if (length < 126) {
      frame.addByte(maskBit | length);
    } else if (length <= 0xffff) {
      frame
        ..addByte(maskBit | 126)
        ..addByte(length >> 8)
        ..addByte(length & 0xff);
    } else {
      frame.addByte(maskBit | 127);
      for (var i = 7; i >= 0; i--) {
        frame.addByte((length >> (8 * i)) & 0xff);
      }
    }
    if (masked) {
      frame
        ..add(mask)
        ..add([for (var i = 0; i < length; i++) payload[i] ^ mask[i & 3]]);
    } else {
      frame.add(payload);
    }
    _socket.add(frame.takeBytes());
  }

  void destroy() => _socket.destroy();
}
