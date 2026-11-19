import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Counts by name, in the order the names first came.
typedef _Counts = Map<String, num>;

void _add(_Counts counts, String name, num count) =>
    counts[name] = (counts[name] ?? 0) + count;

/// The [limit] largest of [counts], the largest first. Equal counts keep
/// the order they came in.
List<MapEntry<String, num>> _largest(_Counts counts, int limit) {
  final entries = counts.entries.toList();
  final order = {for (final (i, e) in entries.indexed) e.key: i};
  entries.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : order[a.key]!.compareTo(order[b.key]!);
  });
  return entries.take(limit).toList();
}

final _digits = RegExp(r'^\d+$');
final _threadNumber = RegExp(r'-\d+$');
final _thousandsGroup = RegExp(r'(\d)(?=(\d{3})+$)');

/// [value] rounded to a whole number, with a comma between thousands.
String _grouped(num value) => value
    .toStringAsFixed(0)
    .replaceAllMapped(_thousandsGroup, (m) => '${m[1]},');

List<String> _words(String line) => [
  for (final word in line.split(RegExp(r'\s+')))
    if (word.isNotEmpty) word,
];

/// The tables of a `kernel` run, from its output directory [out], as
/// Markdown.
///
/// User and system time per request come from the /proc ticks around the
/// time window, with the server's NAPI threads in a column of their own
/// when the run went over veth. System calls per request come from perf's
/// per-thread tracepoint counts and from strace's summary, each over a
/// window of its own, divided by the requests oha completed in that
/// window. strace stops the server at every call, so its windows run
/// slower and batch less.
String kernelReport(Directory out) {
  String? read(String name) {
    final file = File(p.join(out.path, name));
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    return text.isEmpty ? null : text;
  }

  /// The responses oha counted in a window, and its request rate.
  (int, double)? requests(String name) {
    final text = read(name);
    if (text == null) return null;
    final data = jsonDecode(text) as Map<String, dynamic>;
    final statuses = data['statusCodeDistribution'] as Map<String, dynamic>;
    var responses = 0;
    for (final count in statuses.values) {
      responses += count as int;
    }
    if (responses == 0) return null;
    final summary = data['summary'] as Map<String, dynamic>;
    return (responses, (summary['requestsPerSec'] as num).toDouble());
  }

  /// The count and the thread of a `perf stat --per-thread -x,` line whose
  /// event [isEvent] accepts, with the event.
  (int, String, String)? perfLine(String line, bool Function(String) isEvent) {
    if (line.isEmpty || line.startsWith('#')) return null;
    final fields = line.split(',');
    final at = fields.indexWhere(isEvent);
    if (at < 2 || !_digits.hasMatch(fields[at - 2].trim())) return null;
    final thread = fields
        .sublist(0, at - 2)
        .join(',')
        .trim()
        .replaceFirst(_threadNumber, '');
    return (int.parse(fields[at - 2].trim()), thread, fields[at]);
  }

  /// All calls, calls per named syscall and all calls per thread name,
  /// from perf stat over raw_syscalls:sys_enter, which counts every call,
  /// and syscalls:sys_enter_<name> for the named ones.
  (num, _Counts, _Counts)? perfCounts(String name) {
    final text = read(name);
    if (text == null) return null;
    var total = 0;
    final calls = <String, num>{};
    final threads = <String, num>{};
    for (final line in const LineSplitter().convert(text)) {
      final parsed = perfLine(line, (f) => f.contains('sys_enter'));
      if (parsed == null) continue;
      final (count, thread, event) = parsed;
      if (event == 'raw_syscalls:sys_enter') {
        total += count;
        if (count != 0) _add(threads, thread, count);
      } else if (count != 0) {
        _add(calls, event.substring('syscalls:sys_enter_'.length), count);
      }
    }
    return (total, calls, threads);
  }

  /// Calls per syscall, from `strace -c`.
  _Counts? straceCounts(String name) {
    final text = read(name);
    if (text == null) return null;
    final calls = <String, num>{};
    final number = RegExp(r'^[\d.]+$');
    for (final line in const LineSplitter().convert(text)) {
      final tokens = _words(line);
      if (tokens.length < 5 ||
          tokens.last == 'total' ||
          !number.hasMatch(tokens.first)) {
        continue;
      }
      _add(calls, tokens.last, int.parse(tokens[3]));
    }
    return calls;
  }

  /// Each event's count and each thread's instructions, from perf stat
  /// over the PMU.
  (_Counts, _Counts)? counterCounts(String name) {
    final text = read(name);
    if (text == null) return null;
    final events = <String, num>{};
    final threads = <String, num>{};
    for (final line in const LineSplitter().convert(text)) {
      final parsed = perfLine(
        line,
        (f) => f.startsWith('instructions') || f.startsWith('cycles'),
      );
      if (parsed == null) continue;
      final (count, thread, event) = parsed;
      _add(events, event, count);
      if (event.startsWith('instructions')) _add(threads, thread, count);
    }
    return (events, threads);
  }

  /// Percent of the sampled user instructions per library, from
  /// `perf report --sort dso`. JIT code that a perf map names, the VM's
  /// [anon:dart-code] region and anonymous code count as Dart JIT code.
  _Counts? libraryShares(String name) {
    final text = read(name);
    if (text == null) return null;
    final shares = <String, num>{};
    final share = RegExp(r'^\s*([\d.]+)%\s+(\S.*?)\s*$');
    final jit = RegExp(
      r'^(perf-\d+\.map|\[JIT\]|\[unknown\]|//anon|\[anon:dart-code\])',
    );
    for (final line in const LineSplitter().convert(text)) {
      final match = share.firstMatch(line);
      if (match == null) continue;
      var library = match.group(2)!;
      if (jit.hasMatch(library)) library = 'Dart JIT code';
      _add(
        shares,
        library.substring(library.lastIndexOf('/') + 1),
        double.parse(match.group(1)!),
      );
    }
    return shares;
  }

  String top(_Counts counts, int requests, {int limit = 8}) => [
    for (final e in _largest(counts, limit))
      '${e.key} ${(e.value / requests).toStringAsFixed(2)}',
  ].join(', ');

  final buffer = StringBuffer();
  final machine = read('machine.txt') ?? '';
  final ticksPerSecond = int.parse(
    RegExp(r'clock ticks: (\d+)').firstMatch(machine)?.group(1) ?? '100',
  );
  buffer
    ..writeln('# Kernel time per request\n')
    ..writeln('```')
    ..writeln(machine.trim())
    ..writeln('```\n');
  final ticks = [
    for (final line in const LineSplitter().convert(read('ticks.txt') ?? ''))
      _words(line),
  ];
  final napi = ticks.any((t) => t.length == 9);
  buffer.writeln('## User and system time\n');
  if (napi) {
    buffer
      ..writeln(
        'Microseconds of server CPU per request, from /proc over the time '
        'window. NAPI is the system time of the NAPI threads of the '
        "server's end of the veth pair, which the system share counts as "
        'kernel time.\n',
      )
      ..writeln(
        '| server | workload | requests/s | user us | system us | NAPI us | '
        'total us | system share |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|---:|');
  } else {
    buffer
      ..writeln(
        'Microseconds of server CPU per request, from /proc over the time '
        'window.\n',
      )
      ..writeln(
        '| server | workload | requests/s | user us | system us | total us | '
        'system share |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|');
  }
  final order = <(String, String)>[];
  for (final t in ticks) {
    final name = t[0];
    final route = t[1];
    order.add((name, route));
    final window = requests('$name.$route.time.json');
    if (window == null) {
      buffer.writeln(
        '| $name | $route | no requests | | | |${napi ? ' |' : ''}',
      );
      continue;
    }
    final (n, rps) = window;
    double perRequest(String before, String after) =>
        (int.parse(after) - int.parse(before)) / ticksPerSecond / n * 1e6;
    final user = perRequest(t[3], t[5]);
    final system = perRequest(t[4], t[6]);
    final stack = t.length == 9 ? perRequest(t[7], t[8]) : 0.0;
    final total = user + system + stack;
    final share = total == 0 ? 0.0 : (system + stack) / total * 100;
    buffer.writeln(
      '| $name | $route | ${_grouped(rps)} | ${user.toStringAsFixed(2)} | '
      '${system.toStringAsFixed(2)} |'
      '${napi ? ' ${stack.toStringAsFixed(2)} |' : ''} '
      '${total.toStringAsFixed(2)} | ${share.toStringAsFixed(0)}% |',
    );
  }

  final files = [for (final entry in out.listSync()) p.basename(entry.path)];
  if (files.any((name) => name.endsWith('.counters.csv'))) {
    buffer
      ..writeln('\n## Instructions and cycles\n')
      ..writeln(
        'Thousands per request, from perf stat over the PMU, user and '
        'kernel mode'
        '${napi ? ', the NAPI threads of the server end counted with the server' : ''}'
        '.\n',
      )
      ..writeln(
        '| server | workload | requests/s | instructions user | '
        'instructions kernel | kernel share | cycles user | cycles kernel | '
        'threads, k instructions |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---|');
    for (final (name, route) in order) {
      final window = requests('$name.$route.counters.json');
      final counts = counterCounts('$name.$route.counters.csv');
      if (window == null || counts == null) {
        buffer.writeln('| $name | $route | not measured | | | | | | |');
        continue;
      }
      final (n, rps) = window;
      final (events, threads) = counts;
      double thousands(String event) => (events[event] ?? 0) / n / 1e3;
      final userInstructions = thousands('instructions:u');
      final kernelInstructions = thousands('instructions:k');
      final all = userInstructions + kernelInstructions;
      final share = all == 0 ? 0.0 : kernelInstructions / all * 100;
      final byThread = [
        for (final e in _largest(threads, 4))
          '${e.key} ${(e.value / n / 1e3).toStringAsFixed(1)}',
      ].join(', ');
      buffer.writeln(
        '| $name | $route | ${_grouped(rps)} | '
        '${userInstructions.toStringAsFixed(1)} | '
        '${kernelInstructions.toStringAsFixed(1)} | '
        '${share.toStringAsFixed(0)}% | '
        '${thousands('cycles:u').toStringAsFixed(1)} | '
        '${thousands('cycles:k').toStringAsFixed(1)} | $byThread |',
      );
    }
  }

  if (files.any((name) => name.endsWith('.dso.txt'))) {
    buffer
      ..writeln('\n## User instructions by library\n')
      ..writeln(
        'Thousands per request, the user instructions of the counters '
        'window split by the shares of a sampled window of their own. '
        '<name>.<workload>.sym.txt has the functions.\n',
      )
      ..writeln('| server | workload | instructions user | by library |')
      ..writeln('|---|---|---:|---|');
    for (final (name, route) in order) {
      final window = requests('$name.$route.counters.json');
      final counts = counterCounts('$name.$route.counters.csv');
      final shares = libraryShares('$name.$route.dso.txt');
      if (window == null ||
          counts == null ||
          shares == null ||
          shares.isEmpty) {
        buffer.writeln('| $name | $route | not measured | |');
        continue;
      }
      final userInstructions =
          (counts.$1['instructions:u'] ?? 0) / window.$1 / 1e3;
      final libraries = [
        for (final e in _largest(shares, 6))
          '${e.key} ${(userInstructions * e.value / 100).toStringAsFixed(1)}',
      ].join(', ');
      buffer.writeln(
        '| $name | $route | ${userInstructions.toStringAsFixed(1)} | '
        '$libraries |',
      );
    }
  }

  for (final (tool, note) in const [
    (
      'perf',
      'perf stat --per-thread over the syscall tracepoints, no slowdown',
    ),
    ('strace', 'strace -f -c, which stops the server at every call'),
  ]) {
    buffer
      ..writeln('\n## System calls per request, $tool\n')
      ..writeln('$note.\n')
      ..writeln(
        '| server | workload | requests/s | calls per request | largest, '
        'per request | threads, calls per request |',
      )
      ..writeln('|---|---|---:|---:|---|---|');
    for (final (name, route) in order) {
      final window = requests('$name.$route.$tool.json');
      final (num, _Counts, _Counts?)? counts;
      if (tool == 'perf') {
        counts = perfCounts('$name.$route.perf.csv');
      } else {
        final calls = straceCounts('$name.$route.strace.txt');
        counts = calls == null
            ? null
            : (calls.values.fold<num>(0, (a, b) => a + b), calls, null);
      }
      if (window == null || counts == null) {
        buffer.writeln('| $name | $route | not measured | | | |');
        continue;
      }
      final (n, rps) = window;
      final (total, calls, threads) = counts;
      buffer.writeln(
        '| $name | $route | ${_grouped(rps)} | '
        '${(total / n).toStringAsFixed(2)} | ${top(calls, n)} | '
        '${threads == null ? '' : top(threads, n, limit: 4)} |',
      );
    }
  }
  return buffer.toString();
}

/// The functions of a `perf record` window with Dart JIT code named, from
/// the lines of `perf script -F ip,sym,dso` in [samples] and the VM's perf
/// map in [perfMap], when there is one.
///
/// perf names a function from its library's symbol table. The Dart VM
/// names its code region [anon:dart-code], which perf does not take for
/// anonymous memory, so it never reads the VM's `/tmp/perf-<pid>.map`. This
/// names those samples from the map and gives the percent of all samples
/// per library and function, the most first.
String perfSymbols(Iterable<String> samples, {File? perfMap}) {
  final entries = <(int, int, String)>[];
  if (perfMap != null && perfMap.existsSync()) {
    for (final line in perfMap.readAsLinesSync()) {
      final parts = line.split(' ');
      if (parts.length < 3) continue;
      final start = int.tryParse(parts[0], radix: 16);
      final size = int.tryParse(parts[1], radix: 16);
      if (start == null || size == null) continue;
      entries.add((start, size, parts.sublist(2).join(' ')));
    }
  }
  entries.sort((a, b) {
    final byStart = a.$1.compareTo(b.$1);
    if (byStart != 0) return byStart;
    final bySize = a.$2.compareTo(b.$2);
    return bySize != 0 ? bySize : a.$3.compareTo(b.$3);
  });

  String? jitName(int ip) {
    // The last entry that starts at or before ip.
    var low = 0;
    var high = entries.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (entries[middle].$1 <= ip) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return null;
    final (start, size, name) = entries[low - 1];
    return ip < start + size ? name : null;
  }

  final sample = RegExp(r'^\s*([0-9a-f]+)\s+(.*?)\s+\((.*)\)\s*$');
  final offset = RegExp(r'\+0x[0-9a-f]+$');
  final counts = <String, num>{};
  final keys = <String, (String, String)>{};
  var total = 0;
  for (final line in samples) {
    final match = sample.firstMatch(line);
    if (match == null) continue;
    final ip = int.tryParse(match.group(1)!, radix: 16);
    var symbol = match.group(2)!;
    var library = match.group(3)!;
    final file = library.substring(library.lastIndexOf('/') + 1);
    if (file.isNotEmpty) library = file;
    if (symbol == '[unknown]' || symbol.startsWith('0x')) {
      final named = ip == null ? null : jitName(ip);
      symbol = named ?? '[unknown in $library]';
      if (named != null) library = 'Dart JIT code';
    }
    symbol = symbol.replaceFirst(offset, '');
    final key = '$library\u0000$symbol';
    keys[key] = (library, symbol);
    _add(counts, key, 1);
    total++;
  }
  final buffer = StringBuffer()
    ..writeln('# $total samples, ${entries.length} names in the perf map');
  for (final e in _largest(counts, 120)) {
    final (library, symbol) = keys[e.key]!;
    buffer.writeln(
      '${(100 * e.value / total).toStringAsFixed(2).padLeft(6)}%  '
      '${library.padRight(30)} $symbol',
    );
  }
  return buffer.toString();
}
