import 'dart:math' as math;

import 'package:bench_press/bench_press.dart'
    show BenchmarkMetrics, CounterSamples, FiellerInterval;

import 'svg.dart';

/// The two-sided 95% quantile of Student's t for 1 to 30 degrees of
/// freedom.
const _t95 = [
  12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, //
  2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
  2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
];

/// The mean of [samples] and the 95% interval around it, or the mean alone
/// for fewer than two samples.
({double mean, double? low, double? high}) meanInterval(List<double> samples) {
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  if (samples.length < 2) return (mean: mean, low: null, high: null);
  var squares = 0.0;
  for (final sample in samples) {
    squares += (sample - mean) * (sample - mean);
  }
  final deviation = math.sqrt(squares / (samples.length - 1));
  final t = samples.length - 1 <= _t95.length ? _t95[samples.length - 2] : 1.96;
  final half = t * deviation / math.sqrt(samples.length);
  return (mean: mean, low: mean - half, high: mean + half);
}

List<double> _numbers(Object? list) => [
  for (final value in (list as List<dynamic>? ?? const []))
    (value as num).toDouble(),
];

/// A time in nanoseconds with its unit: 49.1 ns, 2.23 us, 1.14 ms.
String formatNanoseconds(double ns) => switch (ns) {
  < 1e3 => '${compact(ns)} ns',
  < 1e6 => '${compact(ns / 1e3)} us',
  < 1e9 => '${compact(ns / 1e6)} ms',
  _ => '${compact(ns / 1e9)} s',
};

Map<String, dynamic> _coordinates(Map<String, dynamic> entry) =>
    entry['coordinates'] as Map<String, dynamic>? ?? const {};

/// The matrix coordinates of [entry], without its group.
Map<String, dynamic> _axes(Map<String, dynamic> entry) =>
    {..._coordinates(entry)}..remove('group');

/// The name of [entry], with its matrix coordinates where it has any.
String _label(Map<String, dynamic> entry) {
  final axes = _axes(entry);
  if (axes.isEmpty) return entry['name'] as String;
  final keys = axes.keys.toList()..sort();
  return '${entry['name']} '
      '(${[for (final key in keys) '$key=${axes[key]}'].join(', ')})';
}

int _processes(Map<String, dynamic> entry) => entry['processes'] as int? ?? 1;

/// The independent time samples of [entry], as the bench_press report takes
/// them: the mean of every process where it ran in more than one, and its
/// trials otherwise.
List<double> _timeSamples(Map<String, dynamic> entry) {
  final means = _processes(entry) > 1
      ? _numbers(entry['process_means_ns'])
      : const <double>[];
  return means.isNotEmpty ? means : _numbers(entry['raw_trials_ns']);
}

CounterSamples? _counters(Map<String, dynamic> entry) =>
    switch (entry['counters']) {
      final Map<String, dynamic> counters => CounterSamples.fromJson(counters),
      _ => null,
    };

List<double> _instructionSamples(Map<String, dynamic> entry) =>
    _counters(entry)?.effectiveInstructions ?? const [];

/// Whether the samples of [a] and [b] pair up, as the bench_press report
/// decides it: both ran in the same number of processes, more than one, on
/// the same target and at the same matrix coordinates.
bool _paired(Map<String, dynamic> a, Map<String, dynamic> b) {
  final axes = _axes(a);
  final others = _axes(b);
  return _processes(a) > 1 &&
      _processes(a) == _processes(b) &&
      a['target'] == b['target'] &&
      axes.length == others.length &&
      axes.entries.every((axis) => others[axis.key] == axis.value);
}

/// The 95% Fieller interval of the ratio of the mean of [numerator] to that
/// of [denominator], or null where the samples bound none.
FiellerInterval? _ratioInterval(
  List<double> numerator,
  List<double> denominator, {
  required bool paired,
}) {
  final interval = FiellerInterval.compute(
    sampleA: numerator,
    sampleB: denominator,
    paired: paired,
  );
  return interval.isValid &&
          !interval.lowerBound.isNaN &&
          !interval.upperBound.isNaN
      ? interval
      : null;
}

/// How the time per operation of [entry] compares with that of [baseline],
/// in the words of the bench_press report: how many times faster or slower
/// its mean is, and the 95% Fieller interval of that ratio.
///
/// The answer is `unresolved` where the report withholds the ratio, since
/// the samples of either are unstable or bound no interval.
String _timeChange(Map<String, dynamic> baseline, Map<String, dynamic> entry) {
  final base = BenchmarkMetrics.fromJson(
    baseline['metrics'] as Map<String, dynamic>,
  );
  final current = BenchmarkMetrics.fromJson(
    entry['metrics'] as Map<String, dynamic>,
  );
  if (!base.isStable || !current.isStable) return 'unresolved';
  final interval = _ratioInterval(
    _timeSamples(baseline),
    _timeSamples(entry),
    paired: _paired(baseline, entry),
  );
  // A speedup interval that reaches zero bounds no slowdown.
  if (interval == null || interval.lowerBound <= 0) return 'unresolved';
  String times(double ratio) => '${ratio.toStringAsFixed(2)}x';
  final speedup = base.meanNs / current.meanNs;
  return speedup >= 1
      ? '${times(speedup)} faster '
            '[${times(interval.lowerBound)}, ${times(interval.upperBound)}]'
      : '${times(1 / speedup)} slower '
            '[${times(1 / interval.upperBound)}, '
            '${times(1 / interval.lowerBound)}]';
}

/// How the instructions per operation of [entry] compare with those of
/// [baseline], in the words of the bench_press report: the change of the
/// mean in percent and the 95% Fieller interval of that change.
///
/// The interval is `N/A` where the report gives none, since the samples of
/// either are unstable or bound no interval. The answer is `-` for two
/// entries counted by different interfaces or in different modes.
String _instructionsChange(
  Map<String, dynamic> baseline,
  Map<String, dynamic> entry,
) {
  final base = _counters(baseline)!;
  final current = _counters(entry)!;
  if (base.source != current.source || base.modes != current.modes) return '-';
  String percent(double ratio) {
    final change = (ratio - 1) * 100;
    if (change.abs() < 0.005) return '0.00%';
    return '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
  }

  final change = percent(current.meanInstructions / base.meanInstructions);
  final interval = base.isStable && current.isStable
      ? _ratioInterval(
          current.effectiveInstructions,
          base.effectiveInstructions,
          paired: _paired(baseline, entry),
        )
      : null;
  return interval == null
      ? '$change [N/A]'
      : '$change [${percent(interval.lowerBound)}, '
            '${percent(interval.upperBound)}]';
}

/// The charts of a bench_press result: instructions per operation where the
/// run counted them, and time per operation.
///
/// A panel holds what the bench_press report compares: the entries of a
/// group, or those of one benchmark without a group, on one target. Every
/// entry carries its change against the baseline of its panel, as that
/// report states it. The benchmarks with nothing to compare with share a
/// last panel.
///
/// Each chart is its name, for the file it goes to, and a function from a
/// theme to its SVG.
List<(String, String Function(PlotTheme))> microCharts(
  Map<String, dynamic> suite,
) {
  final entries = (suite['benchmarks'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final workloads = <(String, String, bool), List<Map<String, dynamic>>>{};
  for (final entry in entries) {
    final group = _coordinates(entry)['group'] as String? ?? '';
    final workload = (
      group.isEmpty ? entry['name'] as String : group,
      entry['target'] as String,
      group.isNotEmpty,
    );
    workloads.putIfAbsent(workload, () => []).add(entry);
  }
  final targets = {for (final entry in entries) entry['target'] as String};
  final environment = suite['environment'] as Map<String, dynamic>? ?? const {};
  final where = [
    targets.join(', '),
    if (environment['dart_version'] case final String dart)
      'Dart ${dart.split(' ').first}',
    if (environment['os'] case final String os) '$os/${environment['arch']}',
  ].join(' · ');
  String titled(String name, String target) => targets.length == 1
      ? name
      : name.isEmpty
      ? target
      : '$name, $target';

  List<BarPanel> panels(
    List<double> Function(Map<String, dynamic> entry) samplesOf,
    String Function(Map<String, dynamic> baseline, Map<String, dynamic> entry)
    change,
  ) {
    final compared = <BarPanel>[];
    final alone = <String, List<Bar>>{};
    for (final MapEntry(key: (name, target, _), value: workload)
        in workloads.entries) {
      final measured = [
        for (final entry in workload)
          if (samplesOf(entry).isNotEmpty) entry,
      ];
      if (measured.isEmpty) continue;
      final baseline = measured.firstWhere(
        (entry) => entry['is_baseline'] == true,
        orElse: () => measured.first,
      );
      Bar bar(Map<String, dynamic> entry, String note) {
        final interval = meanInterval(samplesOf(entry));
        return Bar(
          _label(entry),
          interval.mean,
          low: interval.low,
          high: interval.high,
          note: note,
        );
      }

      if (measured.length == 1) {
        alone.putIfAbsent(target, () => []).add(bar(baseline, ''));
        continue;
      }
      compared.add(
        BarPanel(titled(name, target), [
          bar(baseline, 'baseline'),
          for (final entry in measured)
            if (!identical(entry, baseline))
              bar(entry, change(baseline, entry)),
        ]),
      );
    }
    return [
      ...compared,
      for (final MapEntry(key: target, value: bars) in alone.entries)
        BarPanel(titled('', target), bars),
    ];
  }

  final counters = entries.map(_counters).nonNulls.firstOrNull;
  final instructionPanels = panels(_instructionSamples, _instructionsChange);
  final timePanels = panels(_timeSamples, _timeChange);
  String footnote(List<BarPanel> panels, String brackets) => [
    'Whiskers are the 95% interval of the mean over the trials. Every group '
        'has a scale of its own.',
    if (panels.any((panel) => panel.bars.any((bar) => bar.note.isNotEmpty)))
      brackets,
  ].join('\n');
  return [
    if (counters != null)
      (
        'instructions',
        (theme) => barChart(
          title: 'Instructions per operation',
          subtitle:
              '$where · counted in ${counters.modes} mode by '
              '${counters.source}',
          panels: instructionPanels,
          theme: theme,
          footnote: footnote(
            instructionPanels,
            'Brackets hold the 95% Fieller interval of the change against '
            'the baseline, N/A where samples are unstable.',
          ),
        ),
      ),
    (
      'time',
      (theme) => barChart(
        title: 'Time per operation',
        subtitle: where,
        panels: timePanels,
        theme: theme,
        footnote: footnote(
          timePanels,
          'Brackets hold the 95% Fieller interval of the ratio to the '
          'baseline, unresolved where samples are unstable.',
        ),
        format: formatNanoseconds,
      ),
    ),
  ];
}

/// The charts of an http_load result for [workload]: the saturation rate
/// of each target, the instructions it spent per request where the run
/// counted them, and the p99 latency against the load for the fastest
/// eight. [only] names the targets to draw, all when empty, and [top] caps
/// the bars.
List<(String, String Function(PlotTheme))> loadCharts(
  List<Map<String, dynamic>> measurements, {
  required String workload,
  Set<String> only = const {},
  int top = 24,
}) {
  final rows = [
    for (final m in measurements)
      if (m['workload'] == workload &&
          (only.isEmpty || only.contains(m['target'])))
        m,
  ];
  final full = [
    for (final m in rows)
      if ((m['load'] as num) == 1.0) m,
  ]..sort((a, b) => (b['offeredRps'] as num).compareTo(a['offeredRps'] as num));
  if (full.isEmpty) return const [];
  final drawn = full.take(top).toList();

  Bar bar(Map<String, dynamic> m, List<double> samples, double value) {
    final interval = samples.length > 1 ? meanInterval(samples) : null;
    return Bar(
      m['target'] as String,
      interval?.mean ?? value,
      low: interval?.low,
      high: interval?.high,
    );
  }

  final counted =
      [
        for (final m in drawn)
          if (m['instructionsPerRequest'] != null) m,
      ]..sort(
        (a, b) => (a['instructionsPerRequest'] as num).compareTo(
          b['instructionsPerRequest'] as num,
        ),
      );
  final loads = {for (final m in rows) (m['load'] as num).toDouble()}.toList()
    ..sort();
  final lines = drawn.take(8).map((m) => m['target'] as String).toList();
  const whiskers =
      'Whiskers are the 95% interval of the mean over the closed-loop runs.';
  return [
    (
      '$workload.rate',
      (theme) => barChart(
        title: 'Requests per second at saturation, $workload',
        subtitle: '${drawn.length} of ${full.length} targets, fastest first',
        panels: [
          BarPanel('', [
            for (final m in drawn)
              bar(
                m,
                _numbers(m['saturationRuns']),
                (m['offeredRps'] as num).toDouble(),
              ),
          ]),
        ],
        theme: theme,
        footnote: whiskers,
      ),
    ),
    if (counted.isNotEmpty)
      (
        '$workload.instructions',
        (theme) => barChart(
          title: 'Instructions per request at saturation, $workload',
          subtitle:
              'The server process, ${counted.first['counterModes']} mode, '
              'fewest first',
          panels: [
            BarPanel('', [
              for (final m in counted)
                bar(
                  m,
                  _numbers(m['saturationInstructionsPerRequest']),
                  (m['instructionsPerRequest'] as num).toDouble(),
                ),
            ]),
          ],
          theme: theme,
          footnote: whiskers,
        ),
      ),
    if (loads.length > 1)
      (
        '$workload.p99',
        (theme) => lineChart(
          title: 'p99 latency against load, $workload',
          subtitle: 'Milliseconds, the ${lines.length} fastest targets',
          xLabels: [for (final load in loads) '${(load * 100).round()}%'],
          xTitle: 'Share of the saturation rate offered',
          series: [
            for (final target in lines)
              Series(target, [
                for (final load in loads)
                  (rows
                              .where(
                                (m) =>
                                    m['target'] == target &&
                                    (m['load'] as num) == load,
                              )
                              .firstOrNull?['p99Ms']
                          as num?)
                      ?.toDouble(),
              ]),
          ],
          theme: theme,
        ),
      ),
  ];
}
