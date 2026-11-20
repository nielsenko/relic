/// How the server of a sweep target starts.
enum Launch {
  /// baselines/hyper, with a thread count.
  hyper,

  /// baselines/dusty, with an executor count.
  dusty,

  /// baselines/deno/server.mjs under `deno run`.
  deno,

  /// baselines/bun/server.mjs under `bun run`.
  bun,

  /// bin/load_serve.dart under `dart run`.
  jit,

  /// The `dart build cli` bundle of bin/load_serve.dart.
  aot,

  /// baselines/relic_1_2, Relic 1.2.0 on dart:io, from its own package
  /// configuration.
  relic12;

  /// Whether the server is a Dart program, which runs once per SDK of
  /// DART_SDKS. The others run once.
  bool get isDart => this == jit || this == aot || this == relic12;
}

/// One HTTP target of the sweep: a name, the port its server takes and how
/// the server starts.
final class HttpTarget {
  final String name;
  final int port;
  final Launch launch;

  /// Threads, executors or isolates.
  final int ways;

  /// What load_serve serves for [Launch.jit] and [Launch.aot]: `native`,
  /// `io` or `shelf`, the first two also with a `-handler` suffix.
  final String kind;

  /// Whether the server speaks TLS with the test certificate.
  final bool tls;

  const HttpTarget(
    this.name,
    this.port,
    this.launch,
    this.ways, {
    this.kind = '',
    this.tls = false,
  });

  /// The base URL of the server on [host].
  String url(String host) => '${tls ? 'https' : 'http'}://$host:$port';
}

/// The HTTP targets in the order the sweep runs them and the merged tables
/// list them.
const httpTargets = <HttpTarget>[
  HttpTarget('hyper', 8090, Launch.hyper, 1),
  HttpTarget('hyper4', 8089, Launch.hyper, 4),
  HttpTarget('deno', 8092, Launch.deno, 1),
  HttpTarget('bun', 8094, Launch.bun, 1),
  HttpTarget('dusty', 8093, Launch.dusty, 1),
  HttpTarget('dusty4', 8098, Launch.dusty, 4),
  HttpTarget('relic-native-aot', 18101, Launch.aot, 1, kind: 'native'),
  HttpTarget(
    'relic-native-handler-aot',
    18102,
    Launch.aot,
    1,
    kind: 'native-handler',
  ),
  HttpTarget('relic-native4-aot', 18103, Launch.aot, 4, kind: 'native'),
  HttpTarget('relic-io-aot', 18104, Launch.aot, 1, kind: 'io'),
  HttpTarget('relic-io', 18401, Launch.jit, 1, kind: 'io'),
  HttpTarget('relic-io-handler', 18402, Launch.jit, 1, kind: 'io-handler'),
  HttpTarget('relic-native', 18403, Launch.jit, 1, kind: 'native'),
  HttpTarget(
    'relic-native-handler',
    18404,
    Launch.jit,
    1,
    kind: 'native-handler',
  ),
  HttpTarget('relic-native4', 18441, Launch.jit, 4, kind: 'native'),
  HttpTarget(
    'relic-native4-handler',
    18442,
    Launch.jit,
    4,
    kind: 'native-handler',
  ),
  HttpTarget('shelf', 18405, Launch.jit, 1, kind: 'shelf'),
  HttpTarget('shelf4', 18443, Launch.jit, 4, kind: 'shelf'),
  HttpTarget('hyper-tls', 8490, Launch.hyper, 1, tls: true),
  HttpTarget('hyper4-tls', 8489, Launch.hyper, 4, tls: true),
  HttpTarget('deno-tls', 8492, Launch.deno, 1, tls: true),
  HttpTarget('bun-tls', 8494, Launch.bun, 1, tls: true),
  HttpTarget('dusty-tls', 8493, Launch.dusty, 1, tls: true),
  HttpTarget('dusty4-tls', 8498, Launch.dusty, 4, tls: true),
  HttpTarget('relic-io-tls', 18411, Launch.jit, 1, kind: 'io', tls: true),
  HttpTarget(
    'relic-native-tls',
    18412,
    Launch.jit,
    1,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native-handler-tls',
    18413,
    Launch.jit,
    1,
    kind: 'native-handler',
    tls: true,
  ),
  HttpTarget(
    'relic-native4-tls',
    18451,
    Launch.jit,
    4,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native4-handler-tls',
    18452,
    Launch.jit,
    4,
    kind: 'native-handler',
    tls: true,
  ),
  HttpTarget('shelf-tls', 18414, Launch.jit, 1, kind: 'shelf', tls: true),
  HttpTarget('shelf4-tls', 18453, Launch.jit, 4, kind: 'shelf', tls: true),
  HttpTarget('hyper2', 8190, Launch.hyper, 2),
  HttpTarget('dusty2', 8193, Launch.dusty, 2),
  HttpTarget('relic-native2-aot', 18201, Launch.aot, 2, kind: 'native'),
  HttpTarget('relic-native2', 18421, Launch.jit, 2, kind: 'native'),
  HttpTarget(
    'relic-native2-handler',
    18422,
    Launch.jit,
    2,
    kind: 'native-handler',
  ),
  HttpTarget('shelf2', 18423, Launch.jit, 2, kind: 'shelf'),
  HttpTarget('hyper2-tls', 8590, Launch.hyper, 2, tls: true),
  HttpTarget('dusty2-tls', 8593, Launch.dusty, 2, tls: true),
  HttpTarget(
    'relic-native2-tls',
    18431,
    Launch.jit,
    2,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native2-handler-tls',
    18432,
    Launch.jit,
    2,
    kind: 'native-handler',
    tls: true,
  ),
  HttpTarget('shelf2-tls', 18433, Launch.jit, 2, kind: 'shelf', tls: true),
  HttpTarget('relic-io2', 18424, Launch.jit, 2, kind: 'io'),
  HttpTarget('relic-io4', 18444, Launch.jit, 4, kind: 'io'),
  HttpTarget('relic-io2-tls', 18434, Launch.jit, 2, kind: 'io', tls: true),
  HttpTarget('relic-io4-tls', 18454, Launch.jit, 4, kind: 'io', tls: true),
  HttpTarget(
    'relic-native-aot-tls',
    18501,
    Launch.aot,
    1,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native-handler-aot-tls',
    18502,
    Launch.aot,
    1,
    kind: 'native-handler',
    tls: true,
  ),
  HttpTarget(
    'relic-native2-aot-tls',
    18503,
    Launch.aot,
    2,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native4-aot-tls',
    18504,
    Launch.aot,
    4,
    kind: 'native',
    tls: true,
  ),
  HttpTarget('relic-io-aot-tls', 18505, Launch.aot, 1, kind: 'io', tls: true),
  HttpTarget('hyper8', 8690, Launch.hyper, 8),
  HttpTarget('dusty8', 8693, Launch.dusty, 8),
  HttpTarget('relic-native8-aot', 18801, Launch.aot, 8, kind: 'native'),
  HttpTarget('relic-native8', 18481, Launch.jit, 8, kind: 'native'),
  HttpTarget(
    'relic-native8-handler',
    18482,
    Launch.jit,
    8,
    kind: 'native-handler',
  ),
  HttpTarget('relic-io8', 18483, Launch.jit, 8, kind: 'io'),
  HttpTarget('shelf8', 18484, Launch.jit, 8, kind: 'shelf'),
  HttpTarget('hyper8-tls', 8790, Launch.hyper, 8, tls: true),
  HttpTarget('dusty8-tls', 8793, Launch.dusty, 8, tls: true),
  HttpTarget(
    'relic-native8-aot-tls',
    18802,
    Launch.aot,
    8,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native8-tls',
    18491,
    Launch.jit,
    8,
    kind: 'native',
    tls: true,
  ),
  HttpTarget(
    'relic-native8-handler-tls',
    18492,
    Launch.jit,
    8,
    kind: 'native-handler',
    tls: true,
  ),
  HttpTarget('relic-io8-tls', 18493, Launch.jit, 8, kind: 'io', tls: true),
  HttpTarget('shelf8-tls', 18494, Launch.jit, 8, kind: 'shelf', tls: true),
  HttpTarget('relic12-io', 18121, Launch.relic12, 1),
  HttpTarget('relic12-io2', 18122, Launch.relic12, 2),
  HttpTarget('relic12-io4', 18124, Launch.relic12, 4),
  HttpTarget('relic12-io8', 18128, Launch.relic12, 8),
  HttpTarget('relic12-io-tls', 18521, Launch.relic12, 1, tls: true),
  HttpTarget('relic12-io2-tls', 18522, Launch.relic12, 2, tls: true),
  HttpTarget('relic12-io4-tls', 18524, Launch.relic12, 4, tls: true),
  HttpTarget('relic12-io8-tls', 18528, Launch.relic12, 8, tls: true),
];

/// The targets of the async pass, which loads the routes whose handlers
/// wait: /async, /timer and /db. Only load_serve has them, so only Relic
/// and shelf run there. Their results go to the async directory of the
/// output.
final asyncTargets = [
  for (final name in const [
    'relic-native',
    'relic-native2',
    'relic-native4',
    'relic-native-aot',
    'relic-native2-aot',
    'relic-native4-aot',
    'relic-io',
    'relic-io2',
    'relic-io4',
    'shelf',
    'shelf2',
    'shelf4',
  ])
    httpTargets.firstWhere((target) => target.name == name),
];
