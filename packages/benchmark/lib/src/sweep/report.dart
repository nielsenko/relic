import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'targets.dart';

/// Names older sweeps gave targets, and the names they have now.
const _renamed = <String, String>{
  'native': 'relic-native',
  'native-handler': 'relic-native-handler',
  'native2': 'relic-native2',
  'native2-handler': 'relic-native2-handler',
  'native4': 'relic-native4',
  'native4-handler': 'relic-native4-handler',
  'io': 'relic-io',
  'io2': 'relic-io2',
  'io4': 'relic-io4',
  'io-handler': 'relic-io-handler',
};

/// What each target is, by its name without the `-aot` and `-tls`
/// suffixes: a description, how the server runs, its family in the charts
/// and its threads, executors or isolates.
const _described = <String, (String, String, String, int)>{
  'hyper2': ('bare Rust, 2 threads', 'native', 'other', 2),
  'dusty2': ('bare Zig on zio, 2 executors', 'native', 'other', 2),
  'shelf2': ('shelf on dart:io, 2 isolates', 'JIT', 'other', 2),
  'relic-native2': ('Relic on zio, 2 isolates', 'JIT', 'zio', 2),
  'relic-native2-handler': (
    'Relic on zio, 2 isolates, no router',
    'JIT',
    'zio',
    2,
  ),
  'hyper': ('bare Rust, 1 thread', 'native', 'other', 1),
  'hyper4': ('bare Rust, 4 threads', 'native', 'other', 4),
  'deno': ('bare Deno.serve', 'native', 'other', 1),
  'bun': ('bare Bun.serve', 'native', 'other', 1),
  'dusty': ('bare Zig on zio, 1 executor', 'native', 'other', 1),
  'dusty4': ('bare Zig on zio, 4 executors', 'native', 'other', 4),
  'shelf': ('shelf on dart:io', 'JIT', 'other', 1),
  'shelf4': ('shelf on dart:io, 4 isolates', 'JIT', 'other', 4),
  'relic-io': ('Relic IOAdapter on dart:io', 'JIT', 'ioadapter', 1),
  'relic-io2': (
    'Relic IOAdapter on dart:io, 2 isolates',
    'JIT',
    'ioadapter',
    2,
  ),
  'relic-io4': (
    'Relic IOAdapter on dart:io, 4 isolates',
    'JIT',
    'ioadapter',
    4,
  ),
  'relic-io-handler': (
    'Relic IOAdapter on dart:io, no router',
    'JIT',
    'ioadapter',
    1,
  ),
  'relic-native': ('Relic on zio, 1 isolate', 'JIT', 'zio', 1),
  'relic-native-handler': (
    'Relic on zio, 1 isolate, no router',
    'JIT',
    'zio',
    1,
  ),
  'relic-native4': ('Relic on zio, 4 isolates', 'JIT', 'zio', 4),
  'relic-native4-handler': (
    'Relic on zio, 4 isolates, no router',
    'JIT',
    'zio',
    4,
  ),
  'hyper8': ('bare Rust, 8 threads', 'native', 'other', 8),
  'dusty8': ('bare Zig on zio, 8 executors', 'native', 'other', 8),
  'shelf8': ('shelf on dart:io, 8 isolates', 'JIT', 'other', 8),
  'relic-io8': (
    'Relic IOAdapter on dart:io, 8 isolates',
    'JIT',
    'ioadapter',
    8,
  ),
  'relic-native8': ('Relic on zio, 8 isolates', 'JIT', 'zio', 8),
  'relic-native8-handler': (
    'Relic on zio, 8 isolates, no router',
    'JIT',
    'zio',
    8,
  ),
  'relic12-io': ('Relic 1.2.0 on dart:io', 'JIT', 'other', 1),
  'relic12-io2': ('Relic 1.2.0 on dart:io, 2 isolates', 'JIT', 'other', 2),
  'relic12-io4': ('Relic 1.2.0 on dart:io, 4 isolates', 'JIT', 'other', 4),
  'relic12-io8': ('Relic 1.2.0 on dart:io, 8 isolates', 'JIT', 'other', 8),
};

/// The load fractions the latency columns of a chart row hold, in order.
const _latencyLoads = [0.5, 0.75, 0.9, 0.95, 1.0];

/// [value] rounded to [digits] decimals.
double _round(num value, int digits) =>
    double.parse(value.toStringAsFixed(digits));

/// The population standard deviation of [values].
double _populationDeviation(List<num> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  var squares = 0.0;
  for (final value in values) {
    squares += (value - mean) * (value - mean);
  }
  return math.sqrt(squares / values.length);
}

/// The rows of the report's charts, one per target, from the measurements
/// of http_load in [data]. The fastest plaintext target comes first.
List<Map<String, Object?>> chartRows(List<Map<String, dynamic>> data) {
  final rows = <String, Map<String, Object?>>{};
  Map<String, Object?> rowOf(String target) {
    var name = target;
    final tls = name.endsWith('-tls');
    if (tls) name = name.substring(0, name.length - 4);
    final aot = name.endsWith('-aot');
    var base = aot ? name.substring(0, name.length - 4) : name;
    base = _renamed[base] ?? base;
    name = '$base${aot ? '-aot' : ''}${tls ? '-tls' : ''}';
    final described = _described[base];
    if (described == null) {
      throw FormatException('No description for target $target');
    }
    final (what, mode, family, ways) = described;
    return rows.putIfAbsent(
      name,
      () => {
        'name': name,
        'what': what,
        'mode': aot ? 'AOT' : mode,
        'fam': family,
        'iso': ways,
        'tls': tls,
      },
    );
  }

  for (final m in data) {
    final row = rowOf(m['target'] as String);
    final index = _latencyLoads.indexOf((m['load'] as num).toDouble());
    if (index < 0) continue;
    for (final (column, key) in const [
      ('p50Ms', 'P50'),
      ('p99Ms', 'P99'),
      ('p999Ms', 'P999'),
    ]) {
      final latencies =
          row.putIfAbsent(
                '${m['workload']}$key',
                () => List<Object?>.filled(_latencyLoads.length, null),
              )
              as List<Object?>;
      latencies[index] = _round(m[column] as num, 2);
    }
  }
  for (final m in data) {
    final load = (m['load'] as num).toDouble();
    if (load != 0.9 && load != 0.95 && load != 1.0) continue;
    final row = rowOf(m['target'] as String);
    final workload = m['workload'] as String;
    if (load != 1.0) {
      row['${workload}Open${(load * 100).toInt()}'] = _round(
        (m['rps'] as num) / 1000,
        1,
      );
      continue;
    }
    row[workload] = _round((m['offeredRps'] as num) / 1000, 1);
    if (m.containsKey('cores')) {
      row['${workload}Cores'] = _round(m['cores'] as num, 2);
    }
    row['${workload}Open'] = _round((m['rps'] as num) / 1000, 1);
    final runs = (m['saturationRuns'] as List<dynamic>?)?.cast<num>();
    if (runs != null && runs.isNotEmpty) {
      row['${workload}Runs'] = runs.length;
      row['${workload}Sd'] = _round(_populationDeviation(runs) / 1000, 1);
    }
    // Instructions per request in thousands: the mean over the closed-loop
    // runs and their deviation, and the cycles and kernel share of the
    // open-loop run at full load.
    final instructions =
        (m['saturationInstructionsPerRequest'] as List<dynamic>?)?.cast<num>();
    if (instructions != null && instructions.isNotEmpty) {
      final mean = instructions.reduce((a, b) => a + b) / instructions.length;
      row['${workload}Instr'] = _round(mean / 1000, 1);
      row['${workload}InstrSd'] = _round(
        _populationDeviation(instructions) / 1000,
        1,
      );
    }
    if (m['cyclesPerRequest'] case final num cycles) {
      row['${workload}Cycles'] = _round(cycles / 1000, 1);
    }
    if ((m['kernelInstructionsPerRequest'], m['instructionsPerRequest']) case (
      final num kernel,
      final num all,
    ) when all > 0) {
      row['${workload}Kernel'] = _round(kernel / all, 2);
    }
  }
  final sorted = rows.values.toList();
  for (final row in sorted) {
    if (row['plaintext'] == null) {
      throw FormatException(
        'Target ${row['name']} has no plaintext run at full load',
      );
    }
  }
  // Stable, so targets of the same rate keep the order of the data.
  final order = {for (final (i, row) in sorted.indexed) row: i};
  sorted.sort((a, b) {
    final byRate = (b['plaintext']! as double).compareTo(
      a['plaintext']! as double,
    );
    return byRate != 0 ? byRate : order[a]!.compareTo(order[b]!);
  });
  return sorted;
}

/// [value] as JSON on one line, with a space after every `,` and `:`.
String _spacedJson(Object? value) => switch (value) {
  final Map<String, Object?> map =>
    '{${[for (final e in map.entries) '${jsonEncode(e.key)}: ${_spacedJson(e.value)}'].join(', ')}}',
  final List<Object?> list => '[${list.map(_spacedJson).join(', ')}]',
  _ => jsonEncode(value),
};

/// The `const rows = [...];` JavaScript of the report template for [rows].
String chartRowsSource(List<Map<String, Object?>> rows) {
  final buffer = StringBuffer('const rows = [\n');
  for (final row in rows) {
    buffer.writeln('  ${_spacedJson(row)},');
  }
  buffer.writeln('];');
  return buffer.toString();
}

List<Map<String, dynamic>> _readMeasurements(File file) =>
    (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// Merges the per-target files of the sweep in [sweep] into load.md and
/// load.json in [package], and all.json in [sweep] for the report.
///
/// [how] is the paragraph under the HTTP table: machine, date and anything
/// a reader needs to judge the numbers. The table header comes from
/// http_load's own output. Returns the number of merged measurements and
/// the targets the sweep has no file for.
(int, List<String>) mergeSweep(
  Directory sweep,
  String how, {
  required Directory package,
}) {
  final rows = <Map<String, dynamic>>[];
  final tables = <String, List<String>>{};
  final missing = <String>[];
  for (final target in httpTargets) {
    final json = File(p.join(sweep.path, '${target.name}.json'));
    if (!json.existsSync()) {
      missing.add(target.name);
      continue;
    }
    rows.addAll(_readMeasurements(json));
    tables[target.name] = [
      for (final line in _linesWithEnds(
        File(p.join(sweep.path, '${target.name}.md')).readAsStringSync(),
      ))
        if (line.startsWith('| ') && !line.startsWith('| target')) line,
    ];
  }
  if (tables.isEmpty) {
    throw StateError('No target of the sweep has results in ${sweep.path}');
  }
  final merged = const JsonEncoder.withIndent('  ').convert(rows);
  File(p.join(sweep.path, 'all.json')).writeAsStringSync(merged);
  File(p.join(package.path, 'load.json')).writeAsStringSync(merged);

  final first = httpTargets.firstWhere((t) => tables.containsKey(t.name));
  final head = File(
    p.join(sweep.path, '${first.name}.md'),
  ).readAsLinesSync().take(4).toList();
  final tableHead = head.where((line) => line.startsWith('|')).join('\n');
  String tableOf({required bool tls}) => [
    for (final target in httpTargets)
      if (target.name.endsWith('-tls') == tls) ...?tables[target.name],
  ].join();

  final loadMd = File(p.join(package.path, 'load.md'));
  final old = loadMd.existsSync() ? loadMd.readAsStringSync() : '';
  final wasmAt = old.indexOf('\nThe wasm hosts');
  final text = StringBuffer()
    ..write('${head.first}\n\n$tableHead\n${tableOf(tls: false)}')
    ..write(
      '\n$how The closed-loop rates behind every saturation figure are in '
      'load.json as `saturationRuns`. The `-aot` rows are `dart build cli` '
      'bundles of the same servers, the rest run under `dart run`.\n',
    )
    ..write(
      '\nThe same routes over HTTPS, TLS 1.3 with the relic_native test '
      'certificate, from the same sweep. oha keeps its 64 connections open, '
      'so the cost is per record, not per handshake.\n\n',
    )
    ..write('$tableHead\n${tableOf(tls: true)}')
    ..write(wasmAt < 0 ? '' : old.substring(wasmAt));
  loadMd.writeAsStringSync(text.toString());
  return (rows.length, missing);
}

/// The lines of [text], each with its line end.
Iterable<String> _linesWithEnds(String text) sync* {
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf('\n', start);
    if (end < 0) {
      yield text.substring(start);
      return;
    }
    yield text.substring(start, end + 1);
    start = end + 1;
  }
}

const _countWords = {
  1: 'one',
  2: 'two',
  3: 'three',
  4: 'four',
  5: 'five',
  6: 'six',
};

/// What the page with only Relic and shelf says in place of the full
/// page's text.
const _dartPageSubstitutions = <(String, String)>[
  (
    '<span><i style="background:var(--other)"></i>hyper, dusty, deno, bun, Relic 1.2.0, shelf</span>',
    '<span><i style="background:var(--other)"></i>shelf on dart:io</span>',
  ),
  (
    "<li><b>Threads.</b> hyper runs tokio workers (a current-thread runtime for 1), dusty zio executors, deno and bun one process, the Dart servers isolates each with its own listener on a shared port. The number in a target's name is the count.</li>",
    "<li><b>Isolates.</b> The servers run isolates, each with its own listener on a shared port. The number in a target's name is the count.</li>",
  ),
  (
    ' hyper uses rustls, dusty ztls on AWS-LC, deno and bun their built-in TLS, the Dart servers SecureSocket (dart:io) or tls.zig (relic_native).',
    ' The dart:io servers use SecureSocket, relic_native tls.zig.',
  ),
  ('<h1>Relic Load Sweep</h1>', '<h1>Relic Load Sweep: Relic and shelf</h1>'),
];

/// The `key: value` lines of the sweep's machine.txt, the first of each
/// key, with the tab before the colon of /proc/cpuinfo's lines dropped.
Map<String, String> _machine(Directory sweep) {
  final file = File(p.join(sweep.path, 'machine.txt'));
  if (!file.existsSync()) return const {};
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final at = line.indexOf(':');
    if (at <= 0) continue;
    values.putIfAbsent(
      line.substring(0, at).trim(),
      () => line.substring(at + 1).trim(),
    );
  }
  return values;
}

/// The version of [crate] in the Cargo.lock at [lock], or null.
String? _crateVersion(File lock, String crate) {
  if (!lock.existsSync()) return null;
  final match = RegExp(
    '^name = "${RegExp.escape(crate)}"\nversion = "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock.readAsStringSync());
  return match?.group(1);
}

/// The `?ref=` of [dependency] in the build.zig.zon at [zon], or null.
String? _zigRef(File zon, String dependency) {
  if (!zon.existsSync()) return null;
  final match = RegExp(
    '\\.${RegExp.escape(dependency)} = \\.\\{\\s*\\.url = "[^"]*\\?ref=([^#"]+)',
  ).firstMatch(zon.readAsStringSync());
  return match?.group(1);
}

/// The texts of the template's MACHINESHORT, MACHINE, NETWORK, OHAVERSION,
/// OHATHREADS, SOFTWARE and BASELINES from the sweep's machine.txt and the
/// baselines in [package]. BASELINES is the part the page with Relic and
/// shelf only leaves out.
Map<String, String> _setup(Directory sweep, Directory package) {
  final m = _machine(sweep);
  String? value(String key) => m[key]?.isEmpty ?? true ? null : m[key];
  final instance = value('instance')?.split(' ').last;
  final cpu = value('model name') ?? value('cpu');
  final cores = value('cores');
  final smt = value('smt');
  final short = [?instance, ?cpu].join(', ');
  final machine = [
    if (instance != null) 'GCP $instance',
    ?cpu,
    if (cores != null)
      '$cores CPUs${smt == null || smt == 'on' ? '' : ', one thread per core'}',
    ?value('image'),
    if (value('kernel') case final kernel?) 'Linux $kernel',
  ].join(', ');
  final net = value('net');
  final veth =
      RegExp(
        r'servers on CPUs (\S+), load tools on (\S+), NAPI on (\S+) for vsrv and (\S+) for vcli',
      ).firstMatch(
        File(p.join(sweep.path, 'net.txt')).existsSync()
            ? File(p.join(sweep.path, 'net.txt')).readAsStringSync()
            : '',
      );
  final network = net == 'veth'
      ? 'Servers and load tools run in two network namespaces joined by a '
            'veth pair with threaded NAPI, like two hosts on one link'
            '${veth == null ? '' : ': servers on CPUs ${veth[1]}, load tools on ${veth[2]}, the NAPI threads of each end on ${veth[3]} and ${veth[4]}'}.'
      : 'Servers and load tools run on this one machine over loopback.';
  final load = value('load') ?? '';
  final threads =
      RegExp(r'--oha-threads=(\d+)').firstMatch(load)?.group(1) ?? '4';
  final oha = value('oha') ?? 'oha';
  final baselines = p.join(package.path, 'baselines');
  final hyperLock = File(p.join(baselines, 'hyper', 'Cargo.lock'));
  final zon = File(p.join(baselines, 'dusty', 'build.zig.zon'));
  String version(String key, String name) => value(key) == null
      ? ''
      : ' $name ${value(key)!.replaceFirst(RegExp('^(Dart SDK version: |rustc |deno |zig )'), '').split(' ').first}.';
  final relic = value('relic');
  return {
    'MACHINESHORT': short.isEmpty ? 'one machine' : short,
    'MACHINE': machine.isEmpty ? '' : '$machine.',
    'NETWORK': network,
    'OHAVERSION': oha,
    'OHATHREADS': threads,
    'SOFTWARE': [
      version('dart', 'Dart').trim(),
      if (relic != null) 'Relic at $relic.',
      if (value('zig') case final zig?) 'relic_native on Zig $zig.',
    ].where((part) => part.isNotEmpty).join(' '),
    'BASELINES': [
      '',
      'hyper ${_crateVersion(hyperLock, 'hyper') ?? '?'} on tokio '
          '${_crateVersion(hyperLock, 'tokio') ?? '?'} with rustls '
          '${_crateVersion(hyperLock, 'rustls') ?? '?'}'
          '${value('rustc') == null ? '' : ', ${value('rustc')!.split(' ').take(2).join(' ')}'}.',
      'dusty ${_zigRef(zon, 'dusty') ?? '?'} on zio '
          '${_zigRef(zon, 'zio') ?? '?'}.',
      if (value('deno') case final deno?) 'Deno ${deno.split(' ')[1]}.',
      if (value('bun') case final bun?) 'Bun $bun.',
      'Relic 1.2.0 on dart:io.',
    ].join(' '),
  };
}

/// Builds the two report pages in `report/out` of [package] from the
/// all.json of the sweep in [sweep] and the template
/// `report/relic_bench_template.html`: relic_bench_charts.html with every
/// target, and relic_bench_dart.html with Relic and shelf only.
///
/// The texts that depend on the data, the run count, the load list and the
/// top open-loop point, are filled from all.json. [dates] replaces
/// SWEEPDATES in the methodology. Returns each page's name and row count.
List<(String, int)> buildPages(
  Directory sweep, {
  required Directory package,
  String? dates,
}) {
  final report = p.join(package.path, 'report');
  final data = _readMeasurements(File(p.join(sweep.path, 'all.json')));
  var page = File(
    p.join(report, 'relic_bench_template.html'),
  ).readAsStringSync();
  final start = page.indexOf('const rows = [\n');
  final end = page.indexOf('\n];\n', start) + 4;
  if (start < 0 || end < 4) {
    throw const FormatException('The template has no rows array');
  }
  page =
      page.substring(0, start) +
      chartRowsSource(chartRows(data)) +
      page.substring(end);

  final loads = {for (final m in data) (m['load'] as num).toDouble()}.toList()
    ..sort();
  final runs = {
    for (final m in data)
      if ((m['load'] as num) == 1.0)
        (m['saturationRuns'] as List<dynamic>? ?? const []).length,
  }.toList()..sort();
  final percents = [for (final load in loads) '${(load * 100).toInt()}'];
  final has95 = loads.contains(0.95);
  page = page
      .replaceAll('SATRUNS', _countWords[runs.last] ?? '${runs.last}')
      .replaceAll(
        'LOADLIST',
        '${percents.sublist(0, percents.length - 1).join(', ')} and '
            '${percents.last}',
      )
      .replaceAll('TOPLOAD', has95 ? '95' : '100')
      .replaceAll(
        'NINETY',
        has95
            ? ' The hover also gives what the 90 and 95 percent runs '
                  'delivered.'
            : '',
      )
      .replaceAll(
        'SAFER',
        has95
            ? 'The 90 or 95 percent figure is the safer one to quote there.'
            : 'A rate a little under the bar is the safer one to quote '
                  'there.',
      )
      .replaceAll('SWEEPDATES', dates ?? 'SWEEPDATES');
  final setup = _setup(sweep, package);
  for (final MapEntry(:key, :value) in setup.entries) {
    if (key != 'BASELINES') page = page.replaceAll(key, value);
  }
  // Without the baselines, for the page with Relic and shelf only.
  final relicPage = page.replaceAll('BASELINES', '');
  page = page.replaceAll('BASELINES', setup['BASELINES']!);
  Directory(p.join(report, 'out')).createSync(recursive: true);
  File(
    p.join(report, 'out', 'relic_bench_charts.html'),
  ).writeAsStringSync(page);

  // The page with Relic and shelf only.
  final family = RegExp(r'"fam": "(\w+)"');
  final name = RegExp(r'"name": "([^"]+)"');
  var dartPage = [
    for (final line in relicPage.split('\n'))
      if (!line.startsWith('  {"name"') ||
          const {
            'zio',
            'ioadapter',
          }.contains(family.firstMatch(line)?.group(1)) ||
          (name.firstMatch(line)?.group(1) ?? '').startsWith('shelf'))
        line,
  ].join('\n');
  for (final (from, to) in _dartPageSubstitutions) {
    if (!dartPage.contains(from)) {
      throw FormatException(
        'The template lacks the text: ${from.substring(0, math.min(60, from.length))}',
      );
    }
    dartPage = dartPage.replaceAll(from, to);
  }
  File(
    p.join(report, 'out', 'relic_bench_dart.html'),
  ).writeAsStringSync(dartPage);
  int rowCount(String html) => '  {"name"'.allMatches(html).length;
  return [
    ('relic_bench_charts.html', rowCount(page)),
    ('relic_bench_dart.html', rowCount(dartPage)),
  ];
}
