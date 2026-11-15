import 'dart:io';

/// The CPU time a process has used so far, in seconds, or null when the
/// process cannot be read.
///
/// Linux reads `/proc/<pid>/stat`, at the kernel's clock tick. Elsewhere
/// `ps` reports it, to a hundredth of a second on macOS.
Future<double?> cpuSeconds(int pid) async {
  if (Platform.isLinux) {
    final stat = File('/proc/$pid/stat');
    if (!stat.existsSync()) return null;
    // The command name in parentheses may hold spaces, so the fields are
    // counted from after it.
    final line = stat.readAsStringSync();
    final fields = line.substring(line.lastIndexOf(')') + 2).split(' ');
    final ticks = int.parse(fields[11]) + int.parse(fields[12]);
    return ticks / _clockTicks;
  }
  final result = await Process.run('ps', ['-o', 'cputime=', '-p', '$pid']);
  if (result.exitCode != 0) return null;
  return _parseCpuTime((result.stdout as String).trim());
}

/// The clock ticks per second `/proc` counts in, `getconf CLK_TCK`.
final int _clockTicks = () {
  final result = Process.runSync('getconf', ['CLK_TCK']);
  return result.exitCode == 0
      ? int.parse((result.stdout as String).trim())
      : 100;
}();

/// `[[dd-]hh:]mm:ss[.cc]` as seconds.
double? _parseCpuTime(String text) {
  if (text.isEmpty) return null;
  var days = 0;
  var rest = text;
  final dash = rest.indexOf('-');
  if (dash > 0) {
    days = int.parse(rest.substring(0, dash));
    rest = rest.substring(dash + 1);
  }
  var seconds = days * 86400.0;
  for (final part in rest.split(':')) {
    seconds = seconds * 60 + double.parse(part);
  }
  return seconds;
}

/// The process listening on TCP [port] on this host, or null when none is
/// found. Asks `lsof`.
Future<int?> listeningPid(int port) async {
  final result = await Process.run('lsof', [
    '-t',
    '-iTCP:$port',
    '-sTCP:LISTEN',
  ]);
  if (result.exitCode != 0) return null;
  final pids = (result.stdout as String).trim().split(RegExp(r'\s+'));
  return pids.isEmpty || pids.first.isEmpty ? null : int.parse(pids.first);
}

/// The NAPI threads of network device [device], the kernel threads named
/// `napi/<device>-<id>` while its NAPI is threaded, or none when there are
/// none or this is not Linux.
List<int> napiThreads(String device) {
  if (!Platform.isLinux) return const [];
  final prefix = 'napi/$device-';
  final pids = <int>[];
  for (final entry in Directory('/proc').listSync()) {
    final pid = int.tryParse(entry.path.substring('/proc/'.length));
    if (pid == null) continue;
    try {
      if (File('/proc/$pid/comm').readAsStringSync().startsWith(prefix)) {
        pids.add(pid);
      }
    } on FileSystemException {
      // The process ended between the listing and the read.
    }
  }
  return pids;
}

/// CPU use of a set of processes together over a run.
final class CpuMeter {
  final List<int> pids;
  final Stopwatch _wall = Stopwatch();
  double? _start;

  CpuMeter(this.pids);

  Future<void> begin() async {
    _start = await _seconds();
    _wall
      ..reset()
      ..start();
  }

  /// Cores busy on average since [begin]: CPU seconds over wall seconds.
  Future<double?> end() async {
    _wall.stop();
    final start = _start;
    final stop = await _seconds();
    if (start == null || stop == null) return null;
    return (stop - start) / (_wall.elapsedMicroseconds / 1e6);
  }

  /// The CPU seconds of all [pids], or null when one cannot be read.
  Future<double?> _seconds() async {
    var total = 0.0;
    for (final pid in pids) {
      final seconds = await cpuSeconds(pid);
      if (seconds == null) return null;
      total += seconds;
    }
    return total;
  }
}
