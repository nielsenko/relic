// Starts a server command, drives it with oha, and reports the server's
// CPU time per request as user and system time, read from the kernel's
// per-process counters over the load window. Needs `oha` on the PATH.
//
//   dart run bin/cpu_bench.dart -- dart run bin/hello_serve.dart native 1
//   dart run bin/cpu_bench.dart --connections=64 --seconds=10 -- ./hello 4
//
// The command must listen on --url (default http://127.0.0.1:18099/).
// Its process and the children it forks are measured together, which
// covers a Node cluster or a Go server as well as a Relic one.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

Future<void> main(final List<String> args) async {
  final split = args.indexOf('--');
  if (split < 0 || split == args.length - 1) {
    stderr.writeln(
      'usage: cpu_bench.dart [--connections=N] [--seconds=N] '
      '[--url=U] [--label=L] -- <server command>',
    );
    exitCode = 64;
    return;
  }
  final options = args.sublist(0, split);
  final command = args.sublist(split + 1);
  final connections = int.parse(_option(options, 'connections', '128'));
  final seconds = int.parse(_option(options, 'seconds', '6'));
  final url = _option(options, 'url', 'http://127.0.0.1:18099/');
  final label = _option(options, 'label', command.join(' '));

  if (await _answers(url)) {
    stderr.writeln('Something already serves $url. Stop it first.');
    exitCode = 1;
    return;
  }
  final server = await Process.start(command.first, command.sublist(1));
  unawaited(server.stdout.drain<void>());
  unawaited(server.stderr.drain<void>());
  var pids = [server.pid];
  try {
    await _waitForServer(url);
    await Future<void>.delayed(const Duration(seconds: 1));
    pids = await _processTree(server.pid);
    await _oha(url, connections, 2);
    final before = await _cpuTime(pids);
    final result = await _oha(url, connections, seconds);
    final after = await _cpuTime(pids);
    final user = (after.user - before.user) / 1e9;
    final system = (after.system - before.system) / 1e9;
    final count = (result['statusCodeDistribution'] as Map<String, dynamic>)
        .values
        .fold<int>(0, (final sum, final n) => sum + (n as int));
    final rps =
        ((result['summary'] as Map<String, dynamic>)['requestsPerSec'] as num)
            .toDouble();
    final percentiles = result['latencyPercentiles'] as Map<String, dynamic>;
    double ms(final String key) => (percentiles[key] as num) * 1000;
    stdout.writeln(
      '| $label | ${rps.round()} | ${ms('p50').toStringAsFixed(2)} | '
      '${ms('p99').toStringAsFixed(2)} | '
      '${((user + system) / seconds * 100).round()}% | '
      '${(user / count * 1e6).toStringAsFixed(1)} | '
      '${(system / count * 1e6).toStringAsFixed(1)} | '
      '${((user + system) / count * 1e6).toStringAsFixed(1)} |',
    );
  } finally {
    // The whole tree: a shim that exits after spawning the server leaves
    // the server holding the port and this process's pipes.
    for (final pid in pids) {
      Process.killPid(pid);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (final pid in pids) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
  }
}

/// The server's pid and every descendant. A `dart` shim or a cluster
/// primary puts the process that serves one or more forks down.
Future<List<int>> _processTree(final int pid) async {
  final tree = [pid];
  for (var i = 0; i < tree.length; i++) {
    final children = await Process.run('pgrep', ['-P', '${tree[i]}']);
    for (final line in (children.stdout as String).split('\n')) {
      if (line.trim().isNotEmpty) tree.add(int.parse(line.trim()));
    }
  }
  return tree;
}

Future<void> _waitForServer(final String url) async {
  for (var i = 0; i < 600; i++) {
    if (await _answers(url)) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('The server did not answer at $url');
}

/// Whether a GET of [url] gets a response. Refused, or closed while a
/// server is still starting, is a no.
Future<bool> _answers(final String url) async {
  final client = HttpClient();
  try {
    final response = await client.getUrl(Uri.parse(url)).then((final r) {
      return r.close();
    });
    await response.drain<void>();
    return true;
  } on IOException {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _oha(
  final String url,
  final int connections,
  final int seconds,
) async {
  final result = await Process.run('oha', [
    '--no-tui',
    '--output-format',
    'json',
    '-c',
    '$connections',
    '-z',
    '${seconds}s',
    url,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException('oha', const [], result.stderr as String);
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

/// User and system CPU time in nanoseconds, summed over [pids].
Future<({int user, int system})> _cpuTime(final List<int> pids) async {
  var user = 0;
  var system = 0;
  for (final pid in pids) {
    final t = Platform.isMacOS ? _rusageMacOS(pid) : await _statLinux(pid);
    user += t.user;
    system += t.system;
  }
  return (user: user, system: system);
}

typedef _ProcPidRusageC = Int32 Function(Int32, Int32, Pointer<Uint8>);
typedef _ProcPidRusage = int Function(int, int, Pointer<Uint8>);

/// `proc_pid_rusage` with `RUSAGE_INFO_V0`: a 16 byte uuid, then the user
/// and system times in Mach absolute time units, nanoseconds on Intel and
/// scaled on Apple silicon.
({int user, int system}) _rusageMacOS(final int pid) {
  final rusage = DynamicLibrary.process()
      .lookupFunction<_ProcPidRusageC, _ProcPidRusage>('proc_pid_rusage');
  final buffer = calloc<Uint8>(256);
  try {
    if (rusage(pid, 0, buffer) != 0) {
      // A shim in the tree that has exited since the tree was taken.
      stderr.writeln('proc_pid_rusage failed for pid $pid, counted as 0');
      return (user: 0, system: 0);
    }
    final words = buffer.cast<Uint64>();
    final scale = _machTimebase();
    return (
      user: (words[2] * scale).round(),
      system: (words[3] * scale).round(),
    );
  } finally {
    calloc.free(buffer);
  }
}

typedef _TimebaseC = Int32 Function(Pointer<Uint32>);
typedef _Timebase = int Function(Pointer<Uint32>);

/// Nanoseconds per Mach absolute time unit.
double _machTimebase() {
  final info = DynamicLibrary.process().lookupFunction<_TimebaseC, _Timebase>(
    'mach_timebase_info',
  );
  final buffer = calloc<Uint32>(2);
  try {
    info(buffer);
    return buffer[0] / buffer[1];
  } finally {
    calloc.free(buffer);
  }
}

/// Fields 14 and 15 of `/proc/<pid>/stat`, in clock ticks.
Future<({int user, int system})> _statLinux(final int pid) async {
  final stat = await File('/proc/$pid/stat').readAsString();
  // The command name is in parentheses and may hold spaces.
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  final nsPerTick = 1e9 ~/ _clockTicks();
  return (
    user: int.parse(fields[11]) * nsPerTick,
    system: int.parse(fields[12]) * nsPerTick,
  );
}

typedef _SysconfC = Int64 Function(Int32);
typedef _Sysconf = int Function(int);

int _clockTicks() {
  const scClkTck = 2;
  return DynamicLibrary.process().lookupFunction<_SysconfC, _Sysconf>(
    'sysconf',
  )(scClkTck);
}

String _option(
  final List<String> args,
  final String name,
  final String fallback,
) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return fallback;
}
