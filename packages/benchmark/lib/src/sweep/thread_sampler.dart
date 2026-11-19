import 'dart:async';
import 'dart:io';

/// Busy and total clock ticks of all CPUs so far: user, nice, system,
/// idle, iowait, irq, softirq and steal of /proc/stat, guest time being in
/// user.
(int, int) _machineTicks() {
  final fields = [
    for (final field in File(
      '/proc/stat',
    ).readAsLinesSync().first.split(RegExp(r'\s+')).skip(1).take(8))
      int.parse(field),
  ];
  final total = fields.reduce((a, b) => a + b);
  return (total - fields[3] - fields[4], total);
}

typedef _Thread = ({String process, String name, int ticks, String cpu});

/// Every thread on the machine by process and thread id.
Map<(String, String), _Thread> _threads() {
  final threads = <(String, String), _Thread>{};
  for (final entry in Directory('/proc').listSync()) {
    final pid = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (int.tryParse(pid) == null) continue;
    final String process;
    final List<FileSystemEntity> tasks;
    try {
      process = File(
        '/proc/$pid/comm',
      ).readAsStringSync().trim().replaceAll(' ', '_');
      tasks = Directory('/proc/$pid/task').listSync();
    } on FileSystemException {
      continue;
    }
    for (final task in tasks) {
      final tid = task.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final String stat;
      try {
        stat = File('/proc/$pid/task/$tid/stat').readAsStringSync();
      } on FileSystemException {
        continue;
      }
      // The name in parentheses may hold spaces, so the fields are counted
      // from after it.
      final close = stat.lastIndexOf(')');
      final fields = stat
          .substring(close + 2)
          .split(RegExp(r'\s+'))
          .where((f) => f.isNotEmpty)
          .toList();
      threads[(pid, tid)] = (
        process: process,
        name: stat.substring(stat.indexOf('(') + 1, close).replaceAll(' ', '_'),
        ticks: int.parse(fields[11]) + int.parse(fields[12]),
        cpu: fields[36],
      );
    }
  }
  return threads;
}

/// Samples the CPU time of every thread on the machine once a second,
/// until killed. Linux only.
///
/// Each second writes a machine line to [out], the busy and the total
/// clock ticks of all CPUs since the second before, then a line for every
/// thread that ran: its process's name, pid, thread id, thread name, the
/// CPU it last ran on and its ticks, each line led by the seconds since
/// the start.
Future<Never> sampleThreads(IOSink out) async {
  var previousMachine = _machineTicks();
  var previous = _threads();
  final watch = Stopwatch()..start();
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final machine = _machineTicks();
    final current = _threads();
    final seconds = (watch.elapsedMicroseconds / 1e6).toStringAsFixed(0);
    final lines = [
      '$seconds machine ${machine.$1 - previousMachine.$1} '
          '${machine.$2 - previousMachine.$2}',
    ];
    for (final MapEntry(key: id, value: thread) in current.entries) {
      // A thread born in the last second used all of its ticks in it.
      final ticks = thread.ticks - (previous[id]?.ticks ?? 0);
      if (ticks > 0) {
        lines.add(
          '$seconds ${thread.process} ${id.$1} ${id.$2} ${thread.name} '
          '${thread.cpu} $ticks',
        );
      }
    }
    out.writeln(lines.join('\n'));
    await out.flush();
    previousMachine = machine;
    previous = current;
  }
}
