import 'dart:async';
import 'dart:io';

import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

import '../sweep/paths.dart';
import '../sweep/sweep.dart';

/// The settings of a sweep. Each is also the environment variable the
/// shell script before this took.
enum SweepOption<V> implements OptionDefinition<V> {
  out(
    StringOption(
      argName: 'out',
      envName: 'OUT',
      helpText: 'The output directory, sweep-out in this package by default',
    ),
  ),
  load(
    StringOption(
      argName: 'load',
      envName: 'LOAD',
      helpText:
          'The http_load arguments of every HTTP target. By default the '
          'plaintext, headers and browser workloads on 64 connections, 5 s '
          'a run, five closed-loop runs and open-loop runs at 50, 75, 90, '
          '95 and 100 percent',
    ),
  ),
  rounds(
    IntOption(
      argName: 'rounds',
      envName: 'ROUNDS',
      helpText:
          'How often every HTTP target runs, against a server started anew '
          'each time, all targets once before the next round. With more '
          'than one, each round is in <out>/round-<n>, and the output has '
          'their mean and the spread between them',
      defaultsTo: 2,
      min: 1,
    ),
  ),
  asyncPass(
    IntOption(
      argName: 'async',
      envName: 'ASYNC',
      helpText:
          '1 runs the async pass after the HTTP targets: /async, /timer '
          'and /db on Relic and shelf at 1, 2 and 4 ways',
      defaultsTo: 1,
      min: 0,
      max: 1,
    ),
  ),
  asyncLoad(
    StringOption(
      argName: 'async-load',
      envName: 'ASYNC_LOAD',
      helpText:
          'The http_load arguments of the async pass. As LOAD, on the '
          'async, timer and db workloads',
    ),
  ),
  pgCtl(
    StringOption(
      argName: 'pg-ctl',
      envName: 'PG_CTL',
      helpText:
          'The pg_ctl that starts the postgres behind /db for the async '
          'pass, as user postgres. Without it the pass leaves out db',
      defaultsTo: '',
    ),
  ),
  pgData(
    StringOption(
      argName: 'pg-data',
      envName: 'PG_DATA',
      helpText:
          'The data directory of that postgres, with password postgres '
          'for user postgres and the veth network in pg_hba.conf',
      defaultsTo: '',
    ),
  ),
  loadThreads(
    IntOption(
      argName: 'load-threads',
      envName: 'LOAD_THREADS',
      helpText: 'Threads of zrk and of the WebSocket load client',
      defaultsTo: 4,
      min: 1,
    ),
  ),
  waitForQuiet(
    IntOption(
      argName: 'wait-for-quiet',
      envName: 'QUIET',
      helpText:
          '1 waits for a one-minute load average under 1.5 before every '
          'target, up to 15 minutes. 0 on an instance that runs nothing '
          'else',
      defaultsTo: 1,
      min: 0,
      max: 1,
    ),
  ),
  pause(
    IntOption(
      argName: 'pause',
      envName: 'PAUSE',
      helpText: 'Seconds to wait after a target',
      defaultsTo: 60,
      min: 0,
    ),
  ),
  only(
    StringOption(
      argName: 'only',
      envName: 'ONLY',
      helpText: 'The targets to run, separated by spaces. All by default',
      defaultsTo: '',
    ),
  ),
  sample(
    IntOption(
      argName: 'sample',
      envName: 'SAMPLE',
      helpText:
          '1 records the CPU time of every thread once a second through '
          'each target, in <target>.threads.txt. Linux only',
      defaultsTo: 1,
      min: 0,
      max: 1,
    ),
  ),
  net(
    StringOption(
      argName: 'net',
      envName: 'NET',
      helpText:
          'lo runs the servers and the load tools on the loopback. veth '
          'runs them on the two ends of a veth pair, with the NAPI threads '
          "of the servers' end metered beside them. Linux and sudo only",
      defaultsTo: 'lo',
      allowedValues: ['lo', 'veth'],
    ),
  ),
  vethQueues(
    IntOption(
      argName: 'veth-queues',
      envName: 'VETH_QUEUES',
      helpText:
          'NAPI threads at each end of the veth pair. The CPU count over 8 '
          'from 24 CPUs up and 2 below by default',
      min: 1,
    ),
  ),
  dartSdks(
    StringOption(
      argName: 'dart-sdks',
      envName: 'DART_SDKS',
      helpText:
          'Runs every Dart target once per SDK, from <label>=<sdk '
          'directory> pairs separated by spaces. Each SDK gets a copy of '
          'the repository beside this one and its results in '
          '<out>/dart-<label>',
      defaultsTo: '',
    ),
  ),
  variants(
    StringOption(
      argName: 'variants',
      envName: 'VARIANTS',
      helpText:
          'Runs every Dart target once per variant of this repository, on '
          'the dart of PATH, from <label>=<patch file> pairs separated by '
          'spaces, where an empty patch is the repository as it is. Each '
          'variant gets a copy of the repository beside this one and its '
          'results in <out>/variant-<label>. Not together with --dart-sdks',
      defaultsTo: '',
    ),
  ),
  requirePmu(
    IntOption(
      argName: 'require-pmu',
      envName: 'REQUIRE_PMU',
      helpText:
          '1 stops the sweep before the first target when the machine '
          'gives no hardware counters',
      defaultsTo: 0,
      min: 0,
      max: 1,
    ),
  ),
  wsConnections(
    IntOption(
      argName: 'ws-connections',
      envName: 'WS_CONNECTIONS',
      helpText: 'Connections of a WebSocket echo load',
      defaultsTo: 64,
      min: 1,
    ),
  ),
  wsSeconds(
    IntOption(
      argName: 'ws-seconds',
      envName: 'WS_SECONDS',
      helpText: 'Seconds of a WebSocket echo load, after its warm-up',
      defaultsTo: 10,
      min: 1,
    ),
  ),
  wsWarmup(
    IntOption(
      argName: 'ws-warmup',
      envName: 'WS_WARMUP',
      helpText: 'Seconds of warm-up before a WebSocket echo load',
      defaultsTo: 3,
      min: 0,
    ),
  ),
  wsIdle(
    IntOption(
      argName: 'ws-idle',
      envName: 'WS_IDLE',
      helpText: 'Quiet connections a WebSocket target holds open',
      defaultsTo: 10000,
      min: 1,
    ),
  );

  const SweepOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `sweep`: the load sweep over every target.
final class SweepCommand extends BetterCommand<SweepOption<dynamic>, void> {
  SweepCommand() : super(options: SweepOption.values);

  @override
  final name = 'sweep';

  @override
  final description =
      'Run the load sweep: one http_load run per target, each against a '
      'server started for it alone, then the WebSocket targets. The '
      'baselines must be built first.';

  @override
  Future<void> runWithConfig(
    Configuration<SweepOption<dynamic>> commandConfig,
  ) async {
    final package = packageRoot().path;
    final loadThreads = commandConfig.value(SweepOption.loadThreads);
    String load(SweepOption<String> option, String workloads) =>
        commandConfig.optionalValue(option) ??
        '--workloads=$workloads --connections=64 --seconds=5 '
            '--loads=0.5,0.75,0.9,0.95,1.0 --saturation-runs=5 '
            '--load-threads=$loadThreads';
    final pgCtl = commandConfig.value(SweepOption.pgCtl);
    final sweep = Sweep(
      SweepSettings(
        out: Directory(
          commandConfig.optionalValue(SweepOption.out) ??
              p.join(package, 'sweep-out'),
        ).absolute,
        load: _words(load(SweepOption.load, 'plaintext,headers,browser')),
        rounds: commandConfig.value(SweepOption.rounds),
        asyncPass: commandConfig.value(SweepOption.asyncPass) == 1,
        asyncLoad: _words(
          load(
            SweepOption.asyncLoad,
            pgCtl.isEmpty ? 'async,timer' : 'async,timer,db',
          ),
        ),
        pgCtl: pgCtl,
        pgData: commandConfig.value(SweepOption.pgData),
        quiet: commandConfig.value(SweepOption.waitForQuiet) == 1,
        pause: commandConfig.value(SweepOption.pause),
        only: _words(commandConfig.value(SweepOption.only)).toSet(),
        sample: commandConfig.value(SweepOption.sample) == 1,
        net: commandConfig.value(SweepOption.net),
        vethQueues: commandConfig.optionalValue(SweepOption.vethQueues),
        dartSdks: SweepSettings.parseSdks(
          commandConfig.value(SweepOption.dartSdks),
        ),
        variants: SweepSettings.parseSdks(
          commandConfig.value(SweepOption.variants),
        ),
        loadThreads: loadThreads,
        requirePmu: commandConfig.value(SweepOption.requirePmu) == 1,
        wsConnections: commandConfig.value(SweepOption.wsConnections),
        wsSeconds: commandConfig.value(SweepOption.wsSeconds),
        wsWarmup: commandConfig.value(SweepOption.wsWarmup),
        wsIdle: commandConfig.value(SweepOption.wsIdle),
      ),
      package,
    );
    exitCode = await sweep.run();
  }
}

List<String> _words(String text) => [
  for (final word in text.split(RegExp(r'\s+')))
    if (word.isNotEmpty) word,
];
