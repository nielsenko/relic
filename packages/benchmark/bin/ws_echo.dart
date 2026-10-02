// WebSocket echo round trips per second through one adapter, with
// dart:io clients in isolates of their own (`--client-isolates`, 4 by
// default). The dart:io adapter frames with dart:io's
// WebSocketTransformer, the native one with relic_core's framer over a
// hijacked connection, so the two runs compare the framers.
// `--adapter=shelf` is shelf_web_socket on dart:io, for comparison.
//
//   dart run bin/ws_echo.dart --adapter=native --connections=64 --seconds=10

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:benchmark/src/shelf_server.dart';
import 'package:relic/relic.dart';
import 'package:relic_native/relic_native.dart';
import 'package:web_socket/web_socket.dart'
    show BinaryDataReceived, CloseReceived, TextDataReceived;

Future<void> main(final List<String> args) async {
  final adapter = _arg(args, 'adapter', 'native');
  final connections = int.parse(_arg(args, 'connections', '64'));
  final seconds = int.parse(_arg(args, 'seconds', '10'));
  final size = int.parse(_arg(args, 'size', '64'));
  final binary = _arg(args, 'binary', 'false') == 'true';
  final clientIsolates = int.parse(_arg(args, 'client-isolates', '4'));

  final (:port, :close) = adapter == 'shelf'
      ? await _shelf()
      : await _relic(adapter);
  final url = 'ws://127.0.0.1:$port';

  // The clients run in their own isolates. In the server's isolate they
  // would share its event loop, and the dart:io client would be what the
  // run measures.
  final perIsolate = connections ~/ clientIsolates;
  final runs = await Future.wait([
    for (var i = 0; i < clientIsolates; i++)
      _spawnClients((
        url: url,
        connections: perIsolate,
        seconds: seconds,
        size: size,
        binary: binary,
      )),
  ]);
  final latencies = [for (final run in runs) ...run]..sort();
  stdout.writeln(
    '$adapter: ${(latencies.length / seconds).round()} round trips/s, '
    'p50 ${latencies[latencies.length ~/ 2]} us, '
    'p99 ${latencies[latencies.length * 99 ~/ 100]} us, '
    '${perIsolate * clientIsolates} connections from $clientIsolates '
    'client isolates, $size bytes ${binary ? 'binary' : 'text'}',
  );
  await close();
}

typedef _ClientRun = ({
  String url,
  int connections,
  int seconds,
  int size,
  bool binary,
});

/// Starts [run] in a new isolate and completes with the latency of every
/// round trip, in microseconds.
Future<List<int>> _spawnClients(final _ClientRun run) =>
    Isolate.run(() => _runClients(run));

Future<List<int>> _runClients(final _ClientRun run) async {
  final sockets = [
    for (var i = 0; i < run.connections; i++) await WebSocket.connect(run.url),
  ];
  final text = 'x' * run.size;
  final bytes = Uint8List(run.size);
  var running = true;
  final latencies = <int>[];
  final clock = Stopwatch()..start();

  Future<void> drive(final WebSocket socket) async {
    final echoes = StreamIterator(socket);
    while (running) {
      final sent = clock.elapsedMicroseconds;
      socket.add(run.binary ? bytes : text);
      if (!await echoes.moveNext()) break;
      latencies.add(clock.elapsedMicroseconds - sent);
    }
    await socket.close();
  }

  final drivers = sockets.map(drive).toList();
  await Future<void>.delayed(Duration(seconds: run.seconds));
  running = false;
  await Future.wait(drivers);
  return latencies;
}

typedef _Server = ({int port, Future<void> Function() close});

Future<_Server> _relic(final String adapter) async {
  final server = RelicServer(
    () => adapter == 'io'
        ? IOAdapter.bind(InternetAddress.loopbackIPv4)
        : NativeAdapter.bind(InternetAddress.loopbackIPv4),
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
  return (port: server.port, close: () => server.close(force: true));
}

Future<_Server> _shelf() async {
  final server = await ShelfServer.start(shelfWebSocketEcho, port: 0);
  return (port: server.port, close: () => server.close(force: true));
}

String _arg(final List<String> args, final String name, final String fallback) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return fallback;
}
