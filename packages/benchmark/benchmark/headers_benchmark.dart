// Header access cost per request for a browser's request head: a store
// built per request, as an adapter hands one over, read through the typed
// accessors or in full. The map store, which relic_io fills, is the
// baseline of the byte store relic_native produces.
//
//   dart run bench_press run benchmark/headers_benchmark.dart
import 'package:bench_press/bench_press.dart';
import 'package:benchmark/src/header_stores.dart';
import 'package:relic/relic.dart';

const _request = Throughput.elements(1, unit: 'requests');

final benchmarks = <Object>[
  Benchmark.matrix<(String, int Function(Headers))>(
    cases: [('read3', readThree), ('read_all', readAll)],
    name: (pattern) => 'headers_${pattern.$1}',
    throughput: (_) => _request,
    baseline: (
      'map_store',
      (pattern) => pattern.$2(Headers.fromStore(mapStore())),
    ),
    candidates: {
      'byte_store': (pattern) => pattern.$2(Headers.fromStore(byteStore())),
    },
  ),
];

Future<void> main(List<String> args) => mainBenchmarkSuite(benchmarks, args);
