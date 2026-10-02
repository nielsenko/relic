// A WebSocket echo server for a load tool started elsewhere, such as
// uWebSockets' load_test. Echoes every message on port 18098 until
// SIGTERM.
//
//   dart run bin/ws_echo_serve.dart native   # or: io, shelf
import 'dart:io';

import 'package:benchmark/src/shelf_server.dart';
import 'package:relic/relic.dart';
import 'package:relic_native/relic_native.dart';
import 'package:web_socket/web_socket.dart'
    show BinaryDataReceived, CloseReceived, TextDataReceived;

const _port = 18098;

Future<void> main(final List<String> args) async {
  final kind = args.isEmpty ? 'native' : args[0];
  final Future<void> Function() close;
  if (kind == 'shelf') {
    final server = await ShelfServer.start(shelfWebSocketEcho, port: _port);
    close = () => server.close(force: true);
  } else {
    final server = RelicServer(
      () => kind == 'io'
          ? IOAdapter.bind(InternetAddress.loopbackIPv4, port: _port)
          : NativeAdapter.bind(InternetAddress.loopbackIPv4, port: _port),
    );
    await server.mountAndStart(
      (final req) => WebSocketUpgrade((final ws) {
        ws.events.listen((final event) {
          switch (event) {
            case TextDataReceived(:final text):
              ws.trySendText(text);
            case BinaryDataReceived(:final data):
              ws.trySendBytes(data);
            case CloseReceived():
              break;
          }
        });
      }),
    );
    close = () => server.close(force: true);
  }
  stdout.writeln('ready $pid');
  await ProcessSignal.sigterm.watch().first;
  await close();
}
