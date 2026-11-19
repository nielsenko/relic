import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';

import '../sweep/kernel_report.dart';
import '../sweep/thread_sampler.dart';

enum KernelReportOption<V> implements OptionDefinition<V> {
  out(
    DirOption(
      argPos: 0,
      helpText: 'The output directory of a kernel run',
      mode: PathExistMode.mustExist,
      mandatory: true,
    ),
  );

  const KernelReportOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `kernel-report <kernel-out>`.
final class KernelReportCommand
    extends BetterCommand<KernelReportOption<dynamic>, void> {
  KernelReportCommand() : super(options: KernelReportOption.values);

  @override
  final name = 'kernel-report';

  @override
  final description =
      'Print the tables of a kernel run, from its output directory, as '
      'Markdown';

  @override
  Future<void> runWithConfig(
    Configuration<KernelReportOption<dynamic>> commandConfig,
  ) async {
    stdout.write(kernelReport(commandConfig.value(KernelReportOption.out)));
  }
}

enum PerfSymbolsOption<V> implements OptionDefinition<V> {
  perfMap(
    FileOption(
      argPos: 0,
      helpText: "The Dart VM's perf map, /tmp/perf-<pid>.map",
      mode: PathExistMode.mayExist,
    ),
  );

  const PerfSymbolsOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `perf script -i <data> -F ip,sym,dso | bench perf-symbols [<perf map>]`.
final class PerfSymbolsCommand
    extends BetterCommand<PerfSymbolsOption<dynamic>, void> {
  PerfSymbolsCommand() : super(options: PerfSymbolsOption.values);

  @override
  final name = 'perf-symbols';

  @override
  final description =
      'Read the samples of perf script -F ip,sym,dso from stdin and print '
      'the percent of them per library and function, with Dart JIT code '
      'named from a perf map';

  @override
  Future<void> runWithConfig(
    Configuration<PerfSymbolsOption<dynamic>> commandConfig,
  ) async {
    final samples = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    stdout.write(
      perfSymbols(
        samples,
        perfMap: commandConfig.optionalValue(PerfSymbolsOption.perfMap),
      ),
    );
  }
}

/// `threads > threads.txt`, until killed.
final class ThreadsCommand
    extends BetterCommand<OptionDefinition<dynamic>, void> {
  ThreadsCommand() : super(options: const []);

  @override
  final name = 'threads';

  @override
  final description =
      'Print the clock ticks every thread on the machine used, once a '
      'second, until killed. Linux only.';

  @override
  Future<void> runWithConfig(
    Configuration<OptionDefinition<dynamic>> commandConfig,
  ) => sampleThreads(stdout);
}
