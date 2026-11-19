import 'dart:async';
import 'dart:io';

import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';

import '../sweep/paths.dart';
import '../sweep/report.dart';

enum MergeOption<V> implements OptionDefinition<V> {
  sweep(
    DirOption(
      argPos: 0,
      helpText: 'The output directory of a sweep',
      mode: PathExistMode.mustExist,
      mandatory: true,
    ),
  ),
  how(
    StringOption(
      argPos: 1,
      helpText:
          'The paragraph under the HTTP table: machine, date and anything '
          'a reader needs to judge the numbers',
      mandatory: true,
    ),
  );

  const MergeOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `merge <sweep-dir> "<how the sweep ran>"`.
final class MergeCommand extends BetterCommand<MergeOption<dynamic>, void> {
  MergeCommand() : super(options: MergeOption.values);

  @override
  final name = 'merge';

  @override
  final description =
      "Merge a sweep's per-target files into load.md and load.json of this "
      'package, and all.json in the sweep directory for the report';

  @override
  Future<void> runWithConfig(
    Configuration<MergeOption<dynamic>> commandConfig,
  ) async {
    final (rows, missing) = mergeSweep(
      commandConfig.value(MergeOption.sweep),
      commandConfig.value(MergeOption.how),
      package: packageRoot(),
    );
    stdout.writeln('merged $rows rows, missing: ${missing.join(' ')}');
  }
}

enum ReportOption<V> implements OptionDefinition<V> {
  sweep(
    DirOption(
      argPos: 0,
      helpText: 'The output directory of a merged sweep, with its all.json',
      mode: PathExistMode.mustExist,
      mandatory: true,
    ),
  ),
  dates(
    StringOption(
      argPos: 1,
      helpText: 'When the sweep ran, for the methodology text',
    ),
  );

  const ReportOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `report <sweep-dir> ["<when the sweep ran>"]`.
final class ReportCommand extends BetterCommand<ReportOption<dynamic>, void> {
  ReportCommand() : super(options: ReportOption.values);

  @override
  final name = 'report';

  @override
  final description =
      "Build the two report pages under report/out from a merged sweep's "
      'all.json and report/relic_bench_template.html';

  @override
  Future<void> runWithConfig(
    Configuration<ReportOption<dynamic>> commandConfig,
  ) async {
    final pages = buildPages(
      commandConfig.value(ReportOption.sweep),
      dates: commandConfig.optionalValue(ReportOption.dates),
      package: packageRoot(),
    );
    for (final (page, rows) in pages) {
      stdout.writeln('$page rows $rows');
    }
  }
}
