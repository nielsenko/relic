// The http_load.dart routes for a load tool or profiler started elsewhere.
// Serves them at port 18098, or the fourth argument, until SIGTERM, over
// TLS with the test certificates when the third argument is `tls`. A kind
// with a `-handler` suffix mounts the routes as one handler with no
// router, as http_load's targets do.
//
//   dart --profiler --profile-period=200 --enable-vm-service=8181 \
//       --disable-service-auth-codes bin/load_serve.dart native 1
//   oha -z 20s -c 64 -H ... http://127.0.0.1:18098/browser
//   dart run bin/cpu_profile.dart ws://127.0.0.1:8181/ws --wait=8 --window=6
//
// `shelf` is a shelf server on dart:io with the same routes, for
// comparison.
import 'package:benchmark/src/load_app.dart';
import 'package:benchmark/src/serve.dart';
import 'package:benchmark/src/shelf_server.dart';

Future<void> main(List<String> args) async {
  final target = args.isEmpty ? 'native' : args[0];
  final router = !target.endsWith('-handler');
  final kind = router ? target : target.substring(0, target.length - 8);
  final isolates = args.length < 2 ? 1 : int.parse(args[1]);
  final tls = args.length > 2 && args[2] == 'tls';
  final port = args.length > 3 ? int.parse(args[3]) : 18098;
  final server = await startServer(
    kind,
    router
        ? Served.app(loadApp(), shelfLoad)
        : Served.handler(loadHandler(), shelfLoad),
    port: port,
    isolates: isolates,
    tls: tls,
  );
  await serveUntilSigterm(server);
}
