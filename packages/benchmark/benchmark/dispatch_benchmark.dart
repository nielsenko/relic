// Dispatch overhead of RelicServer with no socket in the way: an
// in-process adapter pushes a thousand exchanges through the sink and the
// run ends when the handler has answered every one. The handler that
// answers at once is the baseline of the one that answers through a
// Future.
//
//   dart run bench_press run benchmark/dispatch_benchmark.dart
import 'dart:async';

import 'package:bench_press/bench_press.dart';
import 'package:benchmark/src/dispatch_adapter.dart';
import 'package:relic/relic.dart';

/// Requests per run.
const _requests = 1000;

final _response = Response.ok(body: Body.fromString('Hello'));

final class Dispatch extends AsyncBenchmark {
  final Handler handler;
  late final ExchangeSink _sink;

  Dispatch(super.name, this.handler, {super.isBaseline})
    : super(group: 'dispatch');

  @override
  Throughput get throughput =>
      const Throughput.elements(_requests, unit: 'requests');

  @override
  Future<void> setup() async => _sink = await startDispatchServer(handler);

  @override
  Future<void> run() {
    final answered = Completer<void>();
    var left = _requests;
    void onRespond() {
      if (--left == 0) answered.complete();
    }

    for (var i = 0; i < _requests; i++) {
      _sink(BenchmarkExchange(onRespond: onRespond));
    }
    return answered.future;
  }
}

final benchmarks = <Object>[
  Dispatch('sync_handler', (_) => _response, isBaseline: true),
  Dispatch('async_handler', (_) async => _response),
];

Future<void> main(List<String> args) => mainBenchmarkSuite(benchmarks, args);
