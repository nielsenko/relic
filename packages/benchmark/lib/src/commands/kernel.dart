import 'dart:async';
import 'dart:io';

import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

import '../sweep/kernel.dart';
import '../sweep/paths.dart';
import '../sweep/sweep.dart' show SweepSettings;

/// The settings of a kernel run. Each is also the environment variable the
/// shell script before this took.
enum KernelOption<V> implements OptionDefinition<V> {
  out(
    StringOption(
      argName: 'out',
      envName: 'OUT',
      helpText: 'The output directory, kernel-out in this package by default',
    ),
  ),
  window(
    IntOption(
      argName: 'window',
      envName: 'WINDOW',
      helpText: 'Seconds of each load window',
      defaultsTo: 10,
      min: 1,
    ),
  ),
  loadThreads(
    IntOption(
      argName: 'load-threads',
      envName: 'LOAD_THREADS',
      helpText: 'Threads of zrk',
      defaultsTo: 4,
      min: 1,
    ),
  ),
  only(
    StringOption(
      argName: 'only',
      envName: 'ONLY',
      helpText:
          'The servers to run, separated by spaces: dartio, relic12-io, '
          'relic-io, shelf, relic-native, hyper, dusty. All by default',
      defaultsTo: '',
    ),
  ),
  net(
    StringOption(
      argName: 'net',
      envName: 'NET',
      helpText:
          'lo, or veth to run the servers and zrk on the two ends of a '
          'veth pair, as in the sweep',
      defaultsTo: 'lo',
      allowedValues: ['lo', 'veth'],
    ),
  ),
  vethQueues(
    IntOption(
      argName: 'veth-queues',
      envName: 'VETH_QUEUES',
      helpText: 'NAPI threads at each end of the veth pair',
      min: 1,
    ),
  ),
  dartSdks(
    StringOption(
      argName: 'dart-sdks',
      envName: 'DART_SDKS',
      helpText:
          'Runs each Dart server once per SDK, from <label>=<sdk '
          'directory> pairs separated by spaces, as in the sweep',
      defaultsTo: '',
    ),
  ),
  sampleEvent(
    StringOption(
      argName: 'sample-event',
      envName: 'SAMPLE_EVENT',
      helpText:
          'What the library window samples. Without a PMU it can be '
          'cpu-clock:u, for the function names alone',
      defaultsTo: 'instructions:u',
    ),
  ),
  samplePeriod(
    IntOption(
      argName: 'sample-period',
      envName: 'SAMPLE_PERIOD',
      helpText: 'One sample in this many events',
      defaultsTo: 1000003,
      min: 1,
    ),
  );

  const KernelOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `kernel`: the kernel's share of a request, per server.
final class KernelCommand extends BetterCommand<KernelOption<dynamic>, void> {
  KernelCommand() : super(options: KernelOption.values);

  @override
  final name = 'kernel';

  @override
  final description =
      "Measure the kernel's share of a request: user and system time, "
      'system calls by name and, with a PMU, instructions and cycles per '
      'request for each server, into kernel.md. Linux only.';

  @override
  Future<void> runWithConfig(
    Configuration<KernelOption<dynamic>> commandConfig,
  ) async {
    final package = packageRoot().path;
    final kernel = Kernel(
      KernelSettings(
        out: Directory(
          commandConfig.optionalValue(KernelOption.out) ??
              p.join(package, 'kernel-out'),
        ).absolute,
        window: commandConfig.value(KernelOption.window),
        loadThreads: commandConfig.value(KernelOption.loadThreads),
        only: {
          for (final name
              in commandConfig.value(KernelOption.only).split(RegExp(r'\s+')))
            if (name.isNotEmpty) name,
        },
        net: commandConfig.value(KernelOption.net),
        vethQueues: commandConfig.optionalValue(KernelOption.vethQueues),
        dartSdks: SweepSettings.parseSdks(
          commandConfig.value(KernelOption.dartSdks),
        ),
        sampleEvent: commandConfig.value(KernelOption.sampleEvent),
        samplePeriod: commandConfig.value(KernelOption.samplePeriod),
      ),
      package,
    );
    exitCode = await kernel.run();
  }
}
