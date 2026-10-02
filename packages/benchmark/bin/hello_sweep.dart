// The hello route over adapters and isolate counts, closed loop through
// oha, with the server's CPU sampled mid-run so the cost per request is
// known once the machine saturates. Needs `oha` on the PATH.
//
//   dart run bin/hello_sweep.dart --configs=native:1,native:4,io:4 \
//       --connections=128 --seconds=6
//
// A config is `native:<isolates>`, `io:<isolates>` or `shelf:<isolates>`,
// the last a shelf server on dart:io for comparison.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:benchmark/src/shelf_server.dart';
import 'package:relic/relic.dart';
import 'package:relic_native/relic_native.dart';

Future<void> main(final List<String> args) async {
  final configs = _arg(
    args,
    'configs',
    'native:1,native:2,native:4,native:8,io:1,io:4',
  ).split(',');
  final connections = int.parse(_arg(args, 'connections', '128'));
  final seconds = int.parse(_arg(args, 'seconds', '6'));

  stdout.writeln(
    '| server | rps | p50 ms | p99 ms | server cpu | us cpu per request |',
  );
  stdout.writeln('|---|---|---|---|---|---|');
  for (final config in configs) {
    final parts = config.split(':');
    final isolates = int.parse(parts[1]);
    final app = RelicApp()
      ..get('/', (final req) => Response.ok(body: Body.fromString('Hello')));
    final Future<void> Function() close;
    switch (parts[0]) {
      case 'shelf':
        final server = await ShelfServer.start(
          shelfHello,
          port: 18099,
          isolates: isolates,
        );
        close = () => server.close(force: true);
      case 'io':
        final server = await app.serve(port: 18099, noOfIsolates: isolates);
        close = () => server.close(force: true);
      default:
        final server = await app.serveNative(
          port: 18099,
          noOfIsolates: isolates,
        );
        close = () => server.close(force: true);
    }
    try {
      final url = 'http://127.0.0.1:18099/';
      await _oha(url, connections, 2);
      final run = _oha(url, connections, seconds);
      // Sample this process while oha is in the middle of the run.
      await Future<void>.delayed(Duration(seconds: seconds ~/ 2));
      final cpu = await _cpuPercent();
      final result = await run;
      final rps = (result['summary']['requestsPerSec'] as num).toDouble();
      final percentiles = result['latencyPercentiles'] as Map<String, dynamic>;
      double ms(final String key) => (percentiles[key] as num) * 1000;
      stdout.writeln(
        '| $config | ${rps.round()} | ${ms('p50').toStringAsFixed(2)} | '
        '${ms('p99').toStringAsFixed(2)} | ${cpu.round()}% | '
        '${(cpu / 100 / rps * 1e6).toStringAsFixed(1)} |',
      );
    } finally {
      await close();
    }
  }
}

Future<Map<String, dynamic>> _oha(
  final String url,
  final int connections,
  final int seconds,
) async {
  final result = await Process.run('oha', [
    '--no-tui',
    '--output-format',
    'json',
    '-c',
    '$connections',
    '-z',
    '${seconds}s',
    url,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException('oha', const [], result.stderr as String);
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

/// This process's CPU as `ps` reports it, 100 being one core.
Future<double> _cpuPercent() async {
  final result = await Process.run('ps', ['-o', '%cpu=', '-p', '$pid']);
  return double.parse((result.stdout as String).trim());
}

String _arg(final List<String> args, final String name, final String fallback) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return fallback;
}
