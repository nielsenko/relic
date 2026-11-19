import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

import '../plot/charts.dart';
import '../plot/kitty.dart';
import '../plot/svg.dart';

enum PlotOption<V> implements OptionDefinition<V> {
  results(
    FileOption(
      argPos: 0,
      helpText:
          'The results to draw: the JSON of bench_press run --save, or the '
          'JSON of http_load or bench merge',
      mode: PathExistMode.mustExist,
      mandatory: true,
    ),
  ),
  out(
    StringOption(
      argName: 'out',
      helpText:
          'The directory of the SVG files, that of the results by default',
    ),
  ),
  workload(
    StringOption(
      argName: 'workload',
      helpText: 'The workload of the load charts',
      defaultsTo: 'plaintext',
    ),
  ),
  only(
    StringOption(
      argName: 'only',
      helpText: 'The targets of the load charts, separated by spaces',
      defaultsTo: '',
    ),
  ),
  top(
    IntOption(
      argName: 'top',
      helpText: 'The most targets a bar chart draws, the fastest ones',
      defaultsTo: 24,
      min: 1,
    ),
  ),
  theme(
    StringOption(
      argName: 'theme',
      helpText: 'The colors of the SVG files',
      defaultsTo: 'light',
      allowedValues: ['light', 'dark'],
    ),
  ),
  terminalTheme(
    StringOption(
      argName: 'terminal-theme',
      helpText: 'The colors of the charts drawn in the terminal',
      defaultsTo: 'dark',
      allowedValues: ['light', 'dark'],
    ),
  ),
  show(
    FlagOption(
      argName: 'show',
      helpText:
          'Draw the charts in the terminal too, where it takes images by '
          'the kitty graphics protocol (kitty, Ghostty, WezTerm, Konsole). '
          'Needs rsvg-convert',
      defaultsTo: true,
    ),
  ),
  columns(
    IntOption(
      argName: 'columns',
      helpText:
          'The terminal columns a chart is drawn over. The width of the '
          'terminal by default, up to 110 columns',
      min: 1,
    ),
  );

  const PlotOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `plot <results.json>`: the results as SVG files, and in the terminal.
final class PlotCommand extends BetterCommand<PlotOption<dynamic>, void> {
  PlotCommand() : super(options: PlotOption.values);

  @override
  final name = 'plot';

  @override
  final description =
      'Draw benchmark results as SVG charts, and in a terminal that takes '
      'images: instructions and time per operation for a bench_press run, '
      'saturation rate, instructions per request and p99 latency for a '
      'load run';

  @override
  Future<void> runWithConfig(
    Configuration<PlotOption<dynamic>> commandConfig,
  ) async {
    final results = commandConfig.value(PlotOption.results);
    final Object? json = jsonDecode(results.readAsStringSync());
    final charts = switch (json) {
      final Map<String, dynamic> suite when suite['benchmarks'] is List =>
        microCharts(suite),
      final List<dynamic> measurements => loadCharts(
        measurements.cast<Map<String, dynamic>>(),
        workload: commandConfig.value(PlotOption.workload),
        only: {
          for (final name
              in commandConfig.value(PlotOption.only).split(RegExp(r'\s+')))
            if (name.isNotEmpty) name,
        },
        top: commandConfig.value(PlotOption.top),
      ),
      _ => throw FormatException(
        '${results.path} is neither a bench_press nor an http_load result',
      ),
    };
    if (charts.isEmpty) {
      stderr.writeln('Nothing to draw in ${results.path}');
      exitCode = 1;
      return;
    }
    final directory = Directory(
      commandConfig.optionalValue(PlotOption.out) ?? results.parent.path,
    )..createSync(recursive: true);
    final stem = p.basenameWithoutExtension(results.path);
    final theme = PlotTheme.named(commandConfig.value(PlotOption.theme));
    final terminal = PlotTheme.named(
      commandConfig.value(PlotOption.terminalTheme),
    );
    var show = commandConfig.value(PlotOption.show) && terminalDrawsImages();
    // A chart is 880 px wide and drawn at twice that, which is about 110
    // columns on a high-density display. A narrower terminal scales it down.
    final columns =
        commandConfig.optionalValue(PlotOption.columns) ??
        (stdout.hasTerminal ? math.min(stdout.terminalColumns, 110) : null);
    for (final (name, draw) in charts) {
      final file = File(p.join(directory.path, '$stem.$name.svg'))
        ..writeAsStringSync(draw(theme));
      stdout.writeln(file.path);
      if (!show) continue;
      final png = await rasterize(draw(terminal));
      if (png == null) {
        stderr.writeln(
          'rsvg-convert is missing or failed, so the charts are not drawn '
          'here.',
        );
        show = false;
        continue;
      }
      // The image leaves the cursor on its last row. The empty line after
      // it keeps the next file name apart from this chart.
      stdout
        ..write(kittyImage(png, columns: columns))
        ..writeln()
        ..writeln();
    }
  }
}
