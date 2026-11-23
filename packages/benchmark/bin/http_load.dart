// HTTP load through a RelicApp on each adapter, driven by zrk from its own
// process. For every target and workload, a closed-loop run finds the
// saturation rate, then open-loop runs at fractions of it report the
// latency percentiles. Needs `zrk` on the PATH.
//
//   dart run bin/http_load.dart --targets=io,native,native4,shelf \
//       --workloads=plaintext,json,headers,browser,alloc,mixed \
//       --connections=64 --seconds=5 --loads=0.5,0.75,1.0 --out=load.md
//
// `--saturation-runs=5` finds the saturation rate as the mean of five
// closed-loop runs. Every run goes into the JSON as `saturationRuns`, so
// the spread behind the rate can be read later.
//
// A `shelf` target is a shelf server on dart:io with the same routes.
// `native-handler` or `io4-handler` mounts the plaintext, headers and
// browser routes as one plain handler, with no router in the path.
// A target that is a URL is a server started elsewhere (Bun, for one)
// that serves the same paths, and `name=URL` labels it in the table, as
// `name=kind` labels a server started here:
//   --targets=relic-io=io,bun=http://127.0.0.1:3000
// `baselines/` has the same routes on bare hyper, on bare Deno.serve, on
// bare Bun.serve and on dusty, a Zig server on the zio relic_native runs
// on.
//
// `--load-threads=N` sizes zrk's pool of threads, 4 by default, so a
// server of four isolates and the load tool together stay within eight
// cores.
//
// `--tls` serves the local targets over TLS with relic_native's test
// certificates. zrk does not verify an https URL.
//
// `--napi-device=vsrv` meters the NAPI threads of network device vsrv
// beside the server, as the server's share of the network stack, when the
// server takes its packets from a device with threaded NAPI, such as one
// end of a veth pair. `bench sweep --net=veth` sets one up.
//
// Where the machine has hardware counters, every run also reads the
// instructions retired and the CPU cycles of the server process, and the
// table gives them per request. macOS always has them. Linux needs a PMU,
// which a GCP instance has when created with PMU=standard, and
// kernel.perf_event_paranoid at 2 or below, at 1 or below for the kernel
// share. The NAPI threads are not counted.

import 'dart:convert';
import 'dart:io';

import 'package:benchmark/src/bench_address.dart';
import 'package:benchmark/src/browser_headers.dart';
import 'package:benchmark/src/counters.dart';
import 'package:benchmark/src/cpu.dart';
import 'package:benchmark/src/load_app.dart';
import 'package:benchmark/src/options.dart';
import 'package:benchmark/src/serve.dart';
import 'package:benchmark/src/shelf_server.dart';
import 'package:benchmark/src/zrk.dart';
import 'package:config/config.dart';

final class Workload {
  final String name;
  final String path;
  final List<String> headers;

  /// The body of a POST, or null for a GET.
  final String? body;
  const Workload(this.name, this.path, [this.headers = const [], this.body]);
}

const _jsonBody = ['Content-Type: application/json'];

final _workloads = [
  const Workload('plaintext', '/plaintext'),
  const Workload('json', '/json'),
  const Workload('headers', '/headers', browserHeaders),
  const Workload('browser', '/browser', browserWithValidator),
  const Workload('browser-json', '/browser-json', browserWithValidator),
  const Workload('browser-utf8', '/browser-utf8', browserWithValidator),
  Workload('read-string', '/read-string', _jsonBody, readDocument),
  const Workload('alloc', '/alloc'),
  const Workload('mixed', '/mixed'),
  const Workload('async', '/async'),
  const Workload('timer', '/timer'),
  const Workload('db', '/db'),
];

final class Measurement {
  final String target;
  final String workload;
  final double load;
  final int offeredRps;
  final double rps;
  final double p50;
  final double p99;
  final double p999;
  final int errors;
  final int nonOk;

  /// Cores the server process kept busy on average, or null when its CPU
  /// time could not be read.
  final double? cores;

  /// Cores the NAPI threads of `--napi-device` kept busy on average, or
  /// null without that option.
  final double? napiCores;

  /// The closed-loop rates whose mean is the saturation rate this run's
  /// [offeredRps] is a fraction of.
  final List<int> saturationRuns;

  /// The coefficient of variation of [saturationRuns].
  final double saturationCv;

  /// Instructions the server spent per request in each of the closed-loop
  /// runs, or empty without hardware counters.
  final List<double> saturationInstructions;

  /// Instructions and cycles the server spent per request over this run, or
  /// null without hardware counters.
  final CounterUse? counters;

  Measurement({
    required this.target,
    required this.workload,
    required this.load,
    required this.offeredRps,
    required this.rps,
    required this.p50,
    required this.p99,
    required this.p999,
    required this.errors,
    required this.nonOk,
    required this.cores,
    required this.napiCores,
    required this.saturationRuns,
    required this.saturationCv,
    required this.saturationInstructions,
    required this.counters,
  });

  Map<String, Object> toJson() => {
    'target': target,
    'workload': workload,
    'load': load,
    'offeredRps': offeredRps,
    'rps': rps,
    'p50Ms': p50,
    'p99Ms': p99,
    'p999Ms': p999,
    'errors': errors,
    'nonOk': nonOk,
    'cores': ?cores,
    'napiCores': ?napiCores,
    'saturationRuns': saturationRuns,
    'saturationCv': saturationCv,
    if (saturationInstructions.isNotEmpty)
      'saturationInstructionsPerRequest': saturationInstructions,
    ...?counters?.toJson(),
  };
}

enum LoadOption<V> implements OptionDefinition<V> {
  targets(
    MultiStringOption(
      argName: 'targets',
      helpText:
          'io, native or shelf, each with an optional isolate count, io or '
          'native with a -handler suffix for a run without the router, or '
          'name=URL for a server started elsewhere',
      defaultsTo: ['io', 'native', 'native4'],
    ),
  ),

  workloads(
    MultiStringOption(
      argName: 'workloads',
      helpText: 'The workloads to run, in order',
      defaultsTo: ['plaintext', 'json', 'headers', 'browser', 'alloc', 'mixed'],
      customValidator: _knownWorkloads,
    ),
  ),

  connections(
    IntOption(
      argName: 'connections',
      helpText: 'Connections zrk keeps open',
      defaultsTo: 64,
      min: 1,
    ),
  ),

  seconds(
    IntOption(
      argName: 'seconds',
      helpText: 'Seconds per run',
      defaultsTo: 5,
      min: 1,
    ),
  ),

  loads(
    MultiOption<double>(
      multiParser: MultiParser(_DoubleParser()),
      argName: 'loads',
      helpText: 'Fractions of the saturation rate to offer',
      defaultsTo: [0.5, 0.75, 1.0],
    ),
  ),

  saturationRuns(
    IntOption(
      argName: 'saturation-runs',
      helpText:
          'Closed-loop runs per workload, the mean of which is the '
          'saturation rate',
      defaultsTo: 1,
      min: 1,
    ),
  ),

  loadThreads(
    IntOption(
      argName: 'load-threads',
      helpText: 'Threads of zrk',
      defaultsTo: 4,
      min: 1,
    ),
  ),

  tls(
    FlagOption(
      argName: 'tls',
      helpText:
          'Serve the io and native targets over TLS with the test '
          'certificates',
      defaultsTo: false,
      negatable: false,
    ),
  ),

  napiDevice(
    StringOption(
      argName: 'napi-device',
      helpText:
          'A network device whose NAPI threads are metered beside the '
          'server, as its share of the network stack',
    ),
  ),

  out(
    StringOption(
      argName: 'out',
      helpText:
          'The file to write the table to. The measurements go beside it '
          'as JSON.',
    ),
  );

  const LoadOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

void _knownWorkloads(List<String> names) {
  for (final name in names) {
    if (!_workloads.any((w) => w.name == name)) {
      throw FormatException('Unknown workload: $name');
    }
  }
}

final class _DoubleParser extends ValueParser<double> {
  const _DoubleParser();

  @override
  double parse(String value) => double.parse(value);
}

const _synopsis = 'usage: dart run bin/http_load.dart [options]';

Future<void> main(List<String> args) async {
  final config = resolveOptions(LoadOption.values, args, synopsis: _synopsis);
  final targets = config.value(LoadOption.targets);
  final connections = config.value(LoadOption.connections);
  final seconds = config.value(LoadOption.seconds);
  final loads = config.value(LoadOption.loads);
  final saturationRuns = config.value(LoadOption.saturationRuns);
  final loadThreads = config.value(LoadOption.loadThreads);
  final tls = config.value(LoadOption.tls);
  final napiDevice = config.optionalValue(LoadOption.napiDevice);
  final out = config.optionalValue(LoadOption.out);
  // Every local target is read before the first run, so a bad one fails
  // fast.
  final local = <String, ({String kind, int isolates, bool router})>{};
  for (final spec in targets) {
    final (target, url, kind) = _split(spec);
    if (url != null) continue;
    local[target] = _parseTarget(kind);
  }

  final workloads = [
    for (final name in config.value(LoadOption.workloads))
      _workloads.firstWhere((w) => w.name == name),
  ];
  final results = <Measurement>[];
  for (final spec in targets) {
    final (target, url, _) = _split(spec);
    final server = url == null ? await _start(local[target]!, tls: tls) : null;
    final base =
        url ??
        '${tls ? 'https' : 'http'}://${benchAddress.address}:${server!.port}';
    stderr.writeln('$target at $base');
    final meter = await _meter(base);
    final counters = meter == null ? null : CounterMeter.open(meter.pids);
    final napi = napiDevice == null ? null : _napiMeter(napiDevice);
    try {
      // One warm-up so JIT and caches are settled before the first number.
      await _zrk(base, workloads.first, connections, 2, null, loadThreads);
      for (final workload in workloads) {
        final closedLoop = <int>[];
        final closedLoopInstructions = <double>[];
        for (var run = 0; run < saturationRuns; run++) {
          counters?.begin();
          final saturation = await _zrk(
            base,
            workload,
            connections,
            seconds,
            null,
            loadThreads,
          );
          final use = counters?.end(saturation.responses);
          closedLoop.add(saturation.rps.round());
          if (use != null) closedLoopInstructions.add(use.instructions);
        }
        final rates = spread([for (final rps in closedLoop) rps.toDouble()]);
        final sat = rates.mean.round();
        final instructions = closedLoopInstructions.isEmpty
            ? null
            : spread(closedLoopInstructions);
        stderr.writeln(
          '  ${workload.name}: saturates at $sat rps '
          '(cv ${_percent(rates.cv)}), runs ${closedLoop.join(' ')}'
          '${instructions == null ? '' : ', ${_thousands(instructions.mean)} k instructions per request (cv ${_percent(instructions.cv)})'}',
        );
        for (final load in loads) {
          final offered = (sat * load).round();
          await meter?.begin();
          await napi?.begin();
          counters?.begin();
          final run = await _zrk(
            base,
            workload,
            connections,
            seconds,
            offered,
            loadThreads,
          );
          final use = counters?.end(run.responses);
          final cores = await meter?.end();
          final napiCores = await napi?.end();
          results.add(
            Measurement(
              target: target,
              workload: workload.name,
              load: load,
              offeredRps: offered,
              rps: run.rps,
              p50: run.p50,
              p99: run.p99,
              p999: run.p999,
              errors: run.failed,
              nonOk: run.nonOk,
              cores: cores,
              napiCores: napiCores,
              saturationRuns: closedLoop,
              saturationCv: rates.cv,
              saturationInstructions: closedLoopInstructions,
              counters: use,
            ),
          );
          stderr.writeln(
            '    ${(load * 100).round()}%: offered $offered, got '
            '${run.rps.round()} rps, p50 ${run.p50.toStringAsFixed(2)} ms, '
            'p99 ${run.p99.toStringAsFixed(2)} ms, '
            'p99.9 ${run.p999.toStringAsFixed(2)} ms'
            '${cores == null ? '' : ', ${cores.toStringAsFixed(2)} cores'}'
            '${napiCores == null ? '' : ', ${napiCores.toStringAsFixed(2)} napi'}'
            '${use == null ? '' : ', ${_thousands(use.instructions)} k instructions'}'
            '${run.failed > 0 ? ', ${run.failed} errors' : ''}',
          );
        }
      }
    } finally {
      counters?.close();
      await server?.close();
    }
  }

  final table = _markdown(
    results,
    connections,
    seconds,
    saturationRuns,
    loadThreads,
  );
  stdout.write(table);
  if (out != null) {
    File(out).writeAsStringSync(table);
    File('${out.replaceAll(RegExp(r'\.md$'), '')}.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(results.map((m) => m.toJson()).toList()),
    );
  }
}

String _percent(double fraction) => '${(fraction * 100).toStringAsFixed(2)}%';

/// [count] in thousands, to one decimal.
String _thousands(double count) => (count / 1000).toStringAsFixed(1);

/// A CPU meter on the process listening at [base], or null when none is
/// found. The server is in this process for the local targets, and whoever
/// listens on the port for the others.
Future<CpuMeter?> _meter(String base) async {
  final port = Uri.parse(base).port;
  final pid = await listeningPid(port);
  if (pid == null) {
    stderr.writeln('  no process found on port $port, no cores column');
    return null;
  }
  return CpuMeter([pid]);
}

/// A CPU meter on the NAPI threads of [device], or null when it has none.
CpuMeter? _napiMeter(String device) {
  final pids = napiThreads(device);
  if (pids.isEmpty) {
    stderr.writeln('  no NAPI threads of $device, no napi cores column');
    return null;
  }
  stderr.writeln('  ${pids.length} NAPI threads of $device');
  return CpuMeter(pids);
}

/// The target name, URL and local kind in [spec].
///
/// `io`, `native4` or `shelf` starts a server here, and `name=native4`
/// labels it. `http://host:port` is a server started elsewhere, and
/// `name=http://host:port` labels it.
(String, String?, String) _split(String spec) {
  final at = spec.indexOf('=');
  final (name, value) = at > 0
      ? (spec.substring(0, at), spec.substring(at + 1))
      : (spec, spec);
  return value.startsWith('http') ? (name, value, value) : (name, null, value);
}

/// The server kind, isolate count and router in [target]: `io`, `native`
/// or `shelf`, or one of them followed by an isolate count, and `-handler`
/// on io or native for the routes as one handler with no router. Anything
/// else is a usage error.
({String kind, int isolates, bool router}) _parseTarget(String target) {
  final match = RegExp(
    r'^(io|native|shelf)(\d*)(-handler)?$',
  ).firstMatch(target);
  if (match == null || (match.group(3) != null && match.group(1) == 'shelf')) {
    usageError('Not a target: $target', LoadOption.values, synopsis: _synopsis);
  }
  return (
    kind: match.group(1)!,
    isolates: int.tryParse(match.group(2)!) ?? 1,
    router: match.group(3) == null,
  );
}

/// A server for [target], as [_parseTarget] read it.
Future<Server> _start(
  ({String kind, int isolates, bool router}) target, {
  required bool tls,
}) {
  final (:kind, :isolates, :router) = target;
  // Port 0 with several dart:io isolates gives each its own port and
  // the server reports the first one, so the dart:io targets take a fixed
  // port.
  return startServer(
    kind,
    router
        ? Served.app(loadApp(), shelfLoad)
        : Served.handler(loadHandler(), shelfLoad),
    port: kind == 'native' ? 0 : 18080,
    isolates: isolates,
    tls: tls,
  );
}

/// One zrk run of [workload] against [base].
///
/// A null [rate] is a closed loop at [connections] in flight, otherwise an
/// open loop at that many requests per second.
Future<ZrkResult> _zrk(
  String base,
  Workload workload,
  int connections,
  int seconds,
  int? rate,
  int threads,
) => runZrk(
  '$base${workload.path}',
  connections: connections,
  seconds: seconds,
  rate: rate,
  headers: workload.headers,
  body: workload.body,
  threads: threads,
);

String _markdown(
  List<Measurement> results,
  int connections,
  int seconds,
  int saturationRuns,
  int loadThreads,
) {
  final napi = results.any((m) => m.napiCores != null);
  final counted = results.any((m) => m.counters != null);
  final kernel = results.any((m) => m.counters?.kernelInstructions != null);
  final buffer = StringBuffer()
    ..writeln(
      '$connections connections from zrk on $loadThreads threads, '
      '${seconds}s per run, saturation the mean of $saturationRuns closed-loop runs, '
      'latency in ms, cores the CPU time the server process used over the '
      'run divided by its wall time'
      '${napi ? ', napi cores the same for the NAPI threads of its network device' : ''}'
      '${counted ? ', k instr and k cycles the thousands of instructions and CPU cycles the server process spent per request' : ''}'
      '${kernel ? ', kernel the share of those instructions spent in kernel mode' : ''}.',
    )
    ..writeln()
    ..writeln(
      '| target | workload | load | offered rps | rps | p50 | p99 | p99.9 '
      '| cores |${napi ? ' napi cores |' : ''}'
      '${counted ? ' k instr | k cycles |' : ''}${kernel ? ' kernel |' : ''} '
      'errors |',
    )
    ..writeln(
      '|---|---|---|---|---|---|---|---|---|${napi ? '---|' : ''}'
      '${counted ? '---|---|' : ''}${kernel ? '---|' : ''}---|',
    );
  for (final m in results) {
    final errors = m.errors > 0 || m.nonOk > 0
        ? '${m.errors} failed, ${m.nonOk} non-200'
        : '-';
    buffer.writeln(
      '| ${m.target} | ${m.workload} | ${(m.load * 100).round()}% | '
      '${m.offeredRps} | ${m.rps.round()} | ${m.p50.toStringAsFixed(2)} | '
      '${m.p99.toStringAsFixed(2)} | ${m.p999.toStringAsFixed(2)} | '
      '${m.cores?.toStringAsFixed(2) ?? '-'} | '
      '${napi ? '${m.napiCores?.toStringAsFixed(2) ?? '-'} | ' : ''}'
      '${counted ? '${_counterCells(m.counters, kernel: kernel)} | ' : ''}'
      '$errors |',
    );
  }
  return buffer.toString();
}

/// The k instr and k cycles cells of a row, and its kernel cell when the
/// table has one.
String _counterCells(CounterUse? use, {required bool kernel}) {
  if (use == null) return kernel ? '- | - | -' : '- | -';
  final kernelInstructions = use.kernelInstructions;
  return [
    _thousands(use.instructions),
    _thousands(use.cycles),
    if (kernel)
      kernelInstructions == null
          ? '-'
          : '${(kernelInstructions / use.instructions * 100).round()}%',
  ].join(' | ');
}
