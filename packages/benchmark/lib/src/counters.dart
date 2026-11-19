import 'dart:io';

import 'package:bench_press/bench_press.dart';

/// The instructions and cycles a server spent per request over a run.
final class CounterUse {
  /// Instructions retired per request, in the modes [modes] names.
  final double instructions;

  /// CPU cycles per request, in the modes [modes] names.
  final double cycles;

  /// The instructions of [instructions] retired in kernel mode, or null where
  /// the platform does not count kernel mode apart.
  final double? kernelInstructions;

  /// The cycles of [cycles] spent in kernel mode, as [kernelInstructions].
  final double? kernelCycles;

  /// `user+kernel`, or `user` where the process may not count kernel mode.
  final String modes;

  CounterUse({
    required this.instructions,
    required this.cycles,
    required this.kernelInstructions,
    required this.kernelCycles,
    required this.modes,
  });

  Map<String, Object> toJson() => {
    'instructionsPerRequest': instructions,
    'cyclesPerRequest': cycles,
    'kernelInstructionsPerRequest': ?kernelInstructions,
    'kernelCyclesPerRequest': ?kernelCycles,
    'counterModes': modes,
  };
}

/// The hardware counters of a set of processes over a run: instructions
/// retired and CPU cycles on every thread, through bench_press's
/// [PerfCounters].
///
/// macOS counts user and kernel mode together. Linux counts them apart,
/// kernel mode only with `kernel.perf_event_paranoid` at 1 or below.
final class CounterMeter {
  final PerfCounters _counters;
  CounterReading? _start;

  CounterMeter._(this._counters);

  /// A meter on [pids], or null where the machine gives no counters, after
  /// writing the reason to stderr.
  static CounterMeter? open(List<int> pids) {
    final counters = PerfCounters.open(
      pids: pids,
      kernel: true,
      onUnavailable: (reason) =>
          stderr.writeln('  no hardware counters: $reason'),
    );
    return counters == null ? null : CounterMeter._(counters);
  }

  void begin() => _start = _counters.read();

  /// What the processes spent per request since [begin], or null when
  /// [requests] is zero.
  CounterUse? end(int requests) {
    final start = _start;
    if (start == null || requests <= 0) return null;
    final stop = _counters.read();
    final kernelInstructions = _delta(
      start.kernelInstructions,
      stop.kernelInstructions,
    );
    final kernelCycles = _delta(start.kernelCycles, stop.kernelCycles);
    return CounterUse(
      instructions:
          (stop.instructions - start.instructions + (kernelInstructions ?? 0)) /
          requests,
      cycles: (stop.cycles - start.cycles + (kernelCycles ?? 0)) / requests,
      kernelInstructions: kernelInstructions == null
          ? null
          : kernelInstructions / requests,
      kernelCycles: kernelCycles == null ? null : kernelCycles / requests,
      modes: kernelInstructions == null ? _counters.modes : 'user+kernel',
    );
  }

  static int? _delta(int? start, int? stop) =>
      start == null || stop == null ? null : stop - start;

  void close() => _counters.close();
}

/// The mean of [samples] and their coefficient of variation, the standard
/// deviation over the mean, by bench_press's [BenchmarkMetrics].
({double mean, double cv}) spread(List<double> samples) {
  final metrics = BenchmarkMetrics.fromSamples(samples);
  return (mean: metrics.meanNs, cv: metrics.cv);
}
