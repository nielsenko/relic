import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// What [command] prints, trimmed, or an empty string when it fails to
/// start. With [mergeStderr] its stderr follows its stdout, as `2>&1`.
Future<String> outputOf(
  List<String> command, {
  Map<String, String>? environment,
  String? workingDirectory,
  bool mergeStderr = false,
}) async {
  try {
    final result = await Process.run(
      command.first,
      command.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
    );
    return '${result.stdout}${mergeStderr ? result.stderr : ''}'.trim();
  } on ProcessException {
    return '';
  }
}

/// Whether [command] exits with 0. A command that fails to start does not.
Future<bool> succeeds(
  List<String> command, {
  Map<String, String>? environment,
}) async {
  try {
    final result = await Process.run(
      command.first,
      command.sublist(1),
      environment: environment,
    );
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The path of [program] on the PATH of [environment], or of this process,
/// or null when it is not there.
String? which(String program, {Map<String, String>? environment}) {
  final path = (environment ?? Platform.environment)['PATH'] ?? '';
  for (final directory in path.split(':')) {
    if (directory.isEmpty) continue;
    final candidate = File('$directory/$program');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

/// Starts [command] with its stdout and stderr written to [log].
///
/// The process ignores SIGHUP when `nohup` is there to start it, so a
/// server outlives the terminal that started the sweep.
Future<Process> startLogged(
  List<String> command,
  File log, {
  Map<String, String>? environment,
  String? workingDirectory,
  bool nohup = false,
}) async {
  final full = [if (nohup && which('nohup') != null) 'nohup', ...command];
  final process = await Process.start(
    full.first,
    full.sublist(1),
    environment: environment,
    workingDirectory: workingDirectory,
  );
  final sink = log.openWrite();
  unawaited(() async {
    try {
      await [
        process.stdout.listen(sink.add).asFuture<void>(),
        process.stderr.listen(sink.add).asFuture<void>(),
      ].wait;
    } on IOException {
      // The process went away with output still in its pipes.
    } finally {
      await sink.close();
    }
  }());
  return process;
}

/// Runs [command] to its end with its stdout in [stdoutFile] and its stderr
/// in [stderrFile]. Without one its stderr goes to [stdoutFile] too, or to
/// the stderr of this process with [passStderr]. Returns its exit code, or
/// 127 when it does not start.
Future<int> runLogged(
  List<String> command, {
  required File stdoutFile,
  File? stderrFile,
  bool passStderr = false,
  Map<String, String>? environment,
  String? workingDirectory,
  bool append = false,
}) async {
  final mode = append ? FileMode.append : FileMode.write;
  final out = stdoutFile.openWrite(mode: mode);
  final StreamConsumer<List<int>> errors = passStderr ? stderr : out;
  final err = stderrFile?.openWrite(mode: mode) ?? errors;
  try {
    final process = await Process.start(
      command.first,
      command.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
    );
    await [
      process.stdout.listen(out.add).asFuture<void>(),
      process.stderr
          .listen(identical(err, stderr) ? stderr.add : (err as IOSink).add)
          .asFuture<void>(),
    ].wait;
    return await process.exitCode;
  } on ProcessException catch (e) {
    stderr.writeln(e);
    return 127;
  } finally {
    await out.close();
    if (err is IOSink && !identical(err, out) && !identical(err, stderr)) {
      await err.close();
    }
  }
}

/// Stops [pid] and the processes it started, with SIGTERM.
Future<void> killTree(int pid) async {
  await succeeds(['pkill', '-P', '$pid']);
  Process.killPid(pid);
}

/// The clock ticks, user and system, a process or thread has used, from
/// the stat file at [path] under /proc, or null when it cannot be read.
(int, int)? ticksOf(String path) {
  final String stat;
  try {
    stat = File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
  // The name in parentheses may hold spaces, so the fields are counted
  // from after it.
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return (int.parse(fields[11]), int.parse(fields[12]));
}

final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

typedef _RlimitC = Int32 Function(Int32, Pointer<_Rlimit>);
typedef _RlimitDart = int Function(int, Pointer<_Rlimit>);

/// `RLIM_INFINITY` as an unsigned word.
const _unlimited = -1;

/// Raises the open-file limit of this process, which the processes it
/// starts inherit, to [wanted] or to the hard limit when that is lower.
/// Returns the soft and the hard limit afterwards, null for unlimited.
(int?, int?) raiseOpenFileLimit(int wanted) {
  final libc = DynamicLibrary.process();
  final getrlimit = libc.lookupFunction<_RlimitC, _RlimitDart>('getrlimit');
  final setrlimit = libc.lookupFunction<_RlimitC, _RlimitDart>('setrlimit');
  final resource = Platform.isMacOS ? 8 : 7; // RLIMIT_NOFILE
  final limit = calloc<_Rlimit>();
  try {
    if (getrlimit(resource, limit) != 0) return (null, null);
    final hard = limit.ref.maximum;
    for (final soft in [wanted, hard]) {
      final tooHigh = hard != _unlimited && (soft == _unlimited || soft > hard);
      if (tooHigh || soft == _unlimited) continue;
      limit.ref.current = soft;
      if (setrlimit(resource, limit) == 0) break;
    }
    getrlimit(resource, limit);
    int? finite(int value) => value == _unlimited || value < 0 ? null : value;
    return (finite(limit.ref.current), finite(limit.ref.maximum));
  } finally {
    calloc.free(limit);
  }
}

/// The open-file limits of this process, soft and hard, as `prlimit` and
/// `ulimit` write them.
(String, String) openFileLimits() {
  final libc = DynamicLibrary.process();
  final getrlimit = libc.lookupFunction<_RlimitC, _RlimitDart>('getrlimit');
  final limit = calloc<_Rlimit>();
  try {
    if (getrlimit(Platform.isMacOS ? 8 : 7, limit) != 0) {
      return ('unlimited', 'unlimited');
    }
    String text(int value) =>
        value == _unlimited || value < 0 ? 'unlimited' : '$value';
    return (text(limit.ref.current), text(limit.ref.maximum));
  } finally {
    calloc.free(limit);
  }
}
