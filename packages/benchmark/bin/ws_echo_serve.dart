// A WebSocket echo server for a load tool started elsewhere, such as the
// sweep's relic_baseline_ws_load or uWebSockets' load_test. Echoes every
// message until SIGTERM, on the port given after the kind (18098 by
// default) with the isolate count given after the port (one by default),
// over TLS with the test certificates when `tls` is among the arguments.
//
//   dart run bin/ws_echo_serve.dart native   # or: io, shelf
//   dart run bin/ws_echo_serve.dart native 18304 4
//   dart run bin/ws_echo_serve.dart native tls
import 'package:benchmark/src/echo_web_socket.dart';
import 'package:benchmark/src/serve.dart';
import 'package:benchmark/src/shelf_server.dart';

Future<void> main(List<String> arguments) async {
  final tls = arguments.contains('tls');
  final args = [
    for (final argument in arguments)
      if (argument != 'tls') argument,
  ];
  final kind = args.isEmpty ? 'native' : args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 18098;
  final isolates = args.length > 2 ? int.parse(args[2]) : 1;
  final server = await startServer(
    kind,
    Served.handler(echoWebSocket, shelfWebSocketEcho),
    port: port,
    isolates: isolates,
    tls: tls,
  );
  await serveUntilSigterm(server);
}
