// Router add and lookup over a thousand routes, static and with two
// parameters, on Relic's Router against routingkit and spanner. Relic is
// the baseline of every group.
//
//   dart run bench_press run benchmark/router_benchmark.dart
//   dart run bench_press run -t aot benchmark/
import 'dart:math';

import 'package:bench_press/bench_press.dart';
import 'package:relic/relic.dart';
import 'package:routingkit/routingkit.dart' as routingkit;
import 'package:spanner/spanner.dart' as spanner;

const routeCount = 1000;
final indexes = List.generate(routeCount, (i) => i);
final permuted = indexes.toList()..shuffle(Random(123));
final staticPaths = [for (final i in permuted) '/path$i'];
final dynamicPaths = [
  for (final i in permuted)
    '/users/user_${Random(i).nextInt(1000)}'
        '/items/item_${Random(i + 1).nextInt(5000)}'
        '/profile$i',
];

const lookups = Throughput.elements(routeCount, unit: 'lookups');
const adds = Throughput.elements(routeCount, unit: 'routes');

Router<int> relicStatic() {
  final router = Router<int>();
  for (final i in indexes) {
    router.get('/path$i', i);
  }
  return router;
}

Router<int> relicDynamic() {
  final router = Router<int>();
  for (final i in indexes) {
    router.get('/users/:id/items/:itemId/profile$i', i);
  }
  return router;
}

routingkit.Router<int> kitStatic() {
  final router = routingkit.createRouter<int>();
  for (final i in indexes) {
    router.add('GET', '/path$i', i);
  }
  return router;
}

routingkit.Router<int> kitDynamic() {
  final router = routingkit.createRouter<int>();
  for (final i in indexes) {
    router.add('GET', '/users/:id/items/:itemId/profile$i', i);
  }
  return router;
}

spanner.Spanner spannerStatic() {
  final router = spanner.Spanner();
  for (final i in indexes) {
    router.addRoute(spanner.HTTPMethod.GET, '/path$i', i);
  }
  return router;
}

spanner.Spanner spannerDynamic() {
  final router = spanner.Spanner();
  for (final i in indexes) {
    router.addRoute(
      spanner.HTTPMethod.GET,
      '/users/<id>/items/<itemId>/profile$i',
      i,
    );
  }
  return router;
}

BenchmarkGroup lookup(
  String name,
  List<String> paths,
  Router<int> relic,
  routingkit.Router<int> kit,
  spanner.Spanner span,
) => BenchmarkGroup('lookup_$name', [
  BenchmarkVariant(
    'relic',
    () {
      var sum = 0;
      for (final path in paths) {
        sum += relic.lookup(Method.get, path).asMatch.value;
      }
      return sum;
    },
    isBaseline: true,
    throughput: lookups,
  ),
  BenchmarkVariant('relic_no_backtrack', () {
    var sum = 0;
    for (final path in paths) {
      sum += relic.lookup(Method.get, path, backtrack: false).asMatch.value;
    }
    return sum;
  }, throughput: lookups),
  BenchmarkVariant('routingkit', () {
    var sum = 0;
    for (final path in paths) {
      sum += kit.find('GET', path)!.data;
    }
    return sum;
  }, throughput: lookups),
  BenchmarkVariant('spanner', () {
    var sum = 0;
    for (final path in paths) {
      sum += span.lookup(spanner.HTTPMethod.GET, path)!.values.length;
    }
    return sum;
  }, throughput: lookups),
]);

final benchmarks = <Object>[
  Benchmark.compare(
    name: 'add_static',
    throughput: adds,
    baseline: ('relic', relicStatic),
    candidates: {'routingkit': kitStatic, 'spanner': spannerStatic},
  ),
  Benchmark.compare(
    name: 'add_dynamic',
    throughput: adds,
    baseline: ('relic', relicDynamic),
    candidates: {'routingkit': kitDynamic, 'spanner': spannerDynamic},
  ),
  lookup('static', staticPaths, relicStatic(), kitStatic(), spannerStatic()),
  lookup(
    'dynamic',
    dynamicPaths,
    relicDynamic(),
    kitDynamic(),
    spannerDynamic(),
  ),
];

void main(List<String> args) => mainBenchmarkSuite(benchmarks, args);
