import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../hdr.dart';

/// Combines the http_load results of [rounds] rounds in `round-<n>` of
/// [out] into the files a sweep of one round has, at the same paths in
/// [out], and returns how many it combined.
///
/// A measurement of a target, workload and load takes the mean over the
/// rounds of each rate, latency, core and counter figure, and the sum of
/// the errors. `saturationRuns` and `saturationInstructionsPerRequest`
/// hold the closed-loop runs of every round, so their spread includes
/// what differs between server starts. `roundSaturation` holds the
/// saturation rate of each round. The table in `<target>.md` lists the
/// rows of every round, with ` r<n>` after the target.
int combineRounds(Directory out, int rounds) {
  final first = Directory(p.join(out.path, 'round-1'));
  if (!first.existsSync()) return 0;
  var combined = 0;
  for (final file in first.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final relative = p.relative(file.path, from: first.path);
    final perRound = [
      for (var round = 1; round <= rounds; round++)
        if (File(p.join(out.path, 'round-$round', relative))
            case final roundFile when roundFile.existsSync())
          _measurements(roundFile),
    ];
    if (perRound.any((measurements) => measurements == null)) continue;
    final rows = combineMeasurements(perRound.cast());
    final target = File(p.join(out.path, relative))
      ..parent.createSync(recursive: true);
    target.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    _combineTables(out, relative.replaceAll(RegExp(r'\.json$'), '.md'), rounds);
    combined++;
  }
  return combined;
}

/// The http_load measurements in [file], or null when it holds something
/// else.
List<Map<String, dynamic>>? _measurements(File file) {
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! List ||
      decoded.isEmpty ||
      decoded.any((m) => m is! Map || !m.containsKey('offeredRps'))) {
    return null;
  }
  return decoded.cast<Map<String, dynamic>>();
}

const _meanFields = [
  'rps',
  'meanMs',
  'p50Ms',
  'p75Ms',
  'p90Ms',
  'p99Ms',
  'p999Ms',
  'p9999Ms',
  'rateRatio',
  'cores',
  'napiCores',
  'instructionsPerRequest',
  'cyclesPerRequest',
  'kernelInstructionsPerRequest',
  'kernelCyclesPerRequest',
];

const _pooledFields = ['saturationRuns', 'saturationInstructionsPerRequest'];

/// The measurements of [rounds], one list per round, combined as
/// [combineRounds] describes. A measurement is matched across rounds by
/// its target, workload and load.
List<Map<String, dynamic>> combineMeasurements(
  List<List<Map<String, dynamic>>> rounds,
) {
  String key(Map<String, dynamic> m) =>
      '${m['target']} ${m['workload']} ${m['load']}';
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final round in rounds) {
    for (final m in round) {
      byKey.putIfAbsent(key(m), () => []).add(m);
    }
  }
  return [
    for (final same in byKey.values)
      {
        ...same.first,
        'offeredRps': _mean([
          for (final m in same) m['offeredRps'] as num,
        ]).round(),
        for (final field in _meanFields)
          if (same.every((m) => m[field] is num))
            field: _mean([for (final m in same) m[field] as num]),
        if (same.every((m) => m['histogram'] is String))
          ..._mergedLatencies([for (final m in same) m['histogram'] as String]),
        for (final field in ['maxMs', 'scheduleLagMs'])
          if (same.every((m) => m[field] is num))
            field: same.map((m) => m[field] as num).reduce(math.max),
        if (same.every((m) => m['errorsByKind'] is Map))
          'errorsByKind': _sumByKind([
            for (final m in same) m['errorsByKind'] as Map<String, dynamic>,
          ]),
        'errors': same.fold<num>(0, (sum, m) => sum + (m['errors'] as num)),
        'nonOk': same.fold<num>(0, (sum, m) => sum + (m['nonOk'] as num)),
        for (final field in _pooledFields)
          if (same.every((m) => m[field] is List))
            field: [
              for (final m in same) ...(m[field] as List<dynamic>).cast<num>(),
            ],
        if (same.every((m) => m['saturationRuns'] is List))
          'saturationCv': _cv([
            for (final m in same)
              ...(m['saturationRuns'] as List<dynamic>).cast<num>(),
          ]),
        'roundSaturation': [
          for (final m in same)
            switch (m['saturationRuns']) {
              final List<dynamic> runs when runs.isNotEmpty => _mean(
                runs.cast<num>(),
              ).round(),
              _ => m['offeredRps'],
            },
        ],
      },
  ];
}

/// The sum of each kind's count over [counts].
Map<String, num> _sumByKind(List<Map<String, dynamic>> counts) {
  final sums = <String, num>{};
  for (final byKind in counts) {
    for (final MapEntry(:key, :value) in byKind.entries) {
      sums[key] = (sums[key] ?? 0) + (value as num);
    }
  }
  return sums;
}

/// The latency fields of the merge of [histograms], one a round, read as
/// zrk reads its own: a round's percentiles do not average into the
/// rounds' percentile, but their histograms merge exactly.
Map<String, Object> _mergedLatencies(List<String> histograms) {
  final merged = Histogram.merge(histograms.map(Histogram.decode));
  double ms(double percentile) => merged.valueAt(percentile) / 1000;
  return {
    'p50Ms': ms(50),
    'p75Ms': ms(75),
    'p90Ms': ms(90),
    'p99Ms': ms(99),
    'p999Ms': ms(99.9),
    'p9999Ms': ms(99.99),
    'histogram': merged.encode(),
  };
}

double _mean(List<num> values) =>
    values.fold<double>(0, (sum, v) => sum + v) / values.length;

double _cv(List<num> values) {
  if (values.isEmpty) return 0;
  final mean = _mean(values);
  if (mean == 0) return 0;
  final squares = values.fold<double>(
    0,
    (sum, v) => sum + (v - mean) * (v - mean),
  );
  return math.sqrt(squares / values.length) / mean;
}

/// Writes the table of [relative] in [out]: the head of round 1's table,
/// then the rows of every round with ` r<n>` after the target.
void _combineTables(Directory out, String relative, int rounds) {
  final lines = <String>[];
  for (var round = 1; round <= rounds; round++) {
    final file = File(p.join(out.path, 'round-$round', relative));
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      final row = line.startsWith('| ') && !line.startsWith('| target');
      if (round > 1 && !row) continue;
      lines.add(
        row
            ? line.replaceFirstMapped(
                RegExp(r'^\| (\S+)'),
                (m) => '| ${m[1]} r$round',
              )
            : line,
      );
    }
  }
  File(p.join(out.path, relative)).writeAsStringSync('${lines.join('\n')}\n');
}
