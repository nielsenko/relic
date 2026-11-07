import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic_core/relic_core.dart';
import 'package:relic_native/relic_native.dart';
import 'package:test/test.dart';

const _upgrade =
    'GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
    'Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n'
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n';

const _acceptKey = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

void main() {
  late NativeAdapter adapter;
  late StreamIterator<AdapterExchange> exchanges;

  setUp(() async {
    adapter = await NativeAdapter.bind(InternetAddress.loopbackIPv4);
    final controller = StreamController<AdapterExchange>();
    adapter.start(controller.add);
    exchanges = StreamIterator(controller.stream);
  });

  tearDown(() => adapter.close(force: true));

  Future<AdapterExchange> nextExchange() async {
    expect(await exchanges.moveNext(), isTrue);
    return exchanges.current;
  }

  Future<String> answerNextRequest() async {
    final plain = await Socket.connect(
      InternetAddress.loopbackIPv4,
      adapter.listeners.first.port,
    );
    plain.write(
      'GET /next HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
    );
    await plain.flush();
    await (await nextExchange()).respond(Response.ok());
    return utf8.decodeStream(plain);
  }

  test(
    'Given an upgraded exchange whose 101 the client has, '
    'when the exchange is aborted, '
    'then the connection closes and the adapter answers the next request',
    () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        adapter.listeners.first.port,
      );
      socket.write(_upgrade);
      await socket.flush();
      final exchange = await nextExchange();
      await exchange.upgradeWebSocket(_acceptKey);
      final head = Completer<void>();
      final received = <int>[];
      final closed = socket.listen((bytes) {
        received.addAll(bytes);
        if (!head.isCompleted && latin1.decode(received).contains('\r\n\r\n')) {
          head.complete();
        }
      }).asFuture<void>();
      await head.future.timeout(const Duration(seconds: 3));

      exchange.abort();

      await closed.timeout(const Duration(seconds: 3));
      expect(latin1.decode(received), startsWith('HTTP/1.1 101 '));
      expect(await answerNextRequest(), startsWith('HTTP/1.1 200 '));
    },
  );

  test(
    'Given an exchange the handler upgraded, '
    'when the exchange is aborted before the 101 is out, '
    'then the connection closes and the adapter answers the next request',
    () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        adapter.listeners.first.port,
      );
      socket.write(_upgrade);
      await socket.flush();
      final exchange = await nextExchange();
      await exchange.upgradeWebSocket(_acceptKey);

      exchange.abort();

      await socket.drain<void>().timeout(const Duration(seconds: 3));
      expect(await answerNextRequest(), startsWith('HTTP/1.1 200 '));
    },
  );

  test(
    'Given a hijacked exchange whose bytes the client has, '
    'when the exchange is aborted, '
    'then the connection closes and the adapter answers the next request',
    () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        adapter.listeners.first.port,
      );
      socket.write('GET /raw HTTP/1.1\r\nHost: localhost\r\n\r\n');
      await socket.flush();
      final exchange = await nextExchange();
      final channel = await exchange.hijack();
      channel.sink.add(utf8.encode('hello'));
      final first = Completer<void>();
      final closed = socket.listen((_) {
        if (!first.isCompleted) first.complete();
      }).asFuture<void>();
      await first.future.timeout(const Duration(seconds: 3));

      exchange.abort();

      await closed.timeout(const Duration(seconds: 3));
      expect(await answerNextRequest(), startsWith('HTTP/1.1 200 '));
    },
  );
}
