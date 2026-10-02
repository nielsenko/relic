// A hello server for a load tool started elsewhere, such as oha or the
// cpu_bench tool here. Serves `Hello` on `/` at port 18099 until SIGTERM.
//
//   dart run bin/hello_serve.dart native 4   # or: io 1, shelf 1
//
// `shelf` is a shelf server on dart:io with the same route, for
// comparison.
import 'dart:io';

import 'package:benchmark/src/shelf_server.dart';
import 'package:relic/relic.dart';
import 'package:relic_native/relic_native.dart';

Future<void> main(final List<String> args) async {
  final kind = args.isEmpty ? 'native' : args[0];
  final isolates = args.length < 2 ? 1 : int.parse(args[1]);
  if (kind == 'shelf') {
    final shelf = await ShelfServer.start(
      shelfHello,
      port: 18099,
      isolates: isolates,
    );
    stdout.writeln('ready $pid');
    await ProcessSignal.sigterm.watch().first;
    await shelf.close(force: true);
    return;
  }
  final app = RelicApp()
    ..get('/', (final req) => Response.ok(body: Body.fromString('Hello')));
  final server = kind == 'io'
      ? await app.serve(port: 18099, noOfIsolates: isolates)
      : await app.serveNative(port: 18099, noOfIsolates: isolates);
  stdout.writeln('ready $pid');
  await ProcessSignal.sigterm.watch().first;
  await server.close(force: true);
}
