// Pulls CPU samples from a running Dart VM and prints where the isolate's
// time goes: by VM tag, by function exclusive, and by function inclusive.
// Start the server with the profiler on and a service port, put load on
// it, then run this against the service.
//
//   dart --profiler --profile-period=200 --enable-vm-service=8181 \
//       --disable-service-auth-codes bin/hello_serve.dart native 1
//   dart run bin/cpu_profile.dart ws://127.0.0.1:8181/ws --wait=8 --window=6
//
// The samples are cleared at the start, the tool waits --wait seconds,
// then reads the last --window seconds of samples.
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(final List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: cpu_profile.dart <ws-uri> [--wait=8] [--window=6] [--top=40]',
    );
    exitCode = 64;
    return;
  }
  final wait = int.parse(_option(args, 'wait', '8'));
  final window = int.parse(_option(args, 'window', '6'));
  final top = int.parse(_option(args, 'top', '40'));

  final service = await vmServiceConnectUri(args.first);
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates!.firstWhere(
      (final i) => i.name == 'main',
      orElse: () =>
          vm.isolates!.firstWhere((final i) => !i.name!.contains('vm-service')),
    );
    await service.clearCpuSamples(isolate.id!);
    await Future<void>.delayed(Duration(seconds: wait));
    final samples = await service.getCpuSamples(isolate.id!, 0, 1 << 62);
    _report(samples, window, top);
  } finally {
    await service.dispose();
  }
}

void _report(final CpuSamples samples, final int window, final int top) {
  final all = samples.samples!;
  if (all.isEmpty) {
    stdout.writeln('no samples');
    return;
  }
  final last = all.last.timestamp!;
  final kept = all.where((final s) => s.timestamp! > last - window * 1000000);
  final functions = samples.functions!;
  final exclusive = <int, int>{};
  final inclusive = <int, int>{};
  final tags = <String, int>{};
  var count = 0;
  for (final sample in kept) {
    count++;
    tags.update(sample.vmTag ?? '?', (final n) => n + 1, ifAbsent: () => 1);
    final stack = sample.stack!;
    if (stack.isEmpty) continue;
    exclusive.update(stack[0], (final n) => n + 1, ifAbsent: () => 1);
    for (final f in stack.toSet()) {
      inclusive.update(f, (final n) => n + 1, ifAbsent: () => 1);
    }
  }
  String name(final int i) {
    final f = functions[i];
    final fn = f.function;
    final owner = fn is FuncRef && fn.owner is ClassRef
        ? '${(fn.owner as ClassRef).name}.'
        : '';
    final url = (f.resolvedUrl ?? '')
        .replaceFirst(RegExp(r'^.*/lib/'), '')
        .replaceFirst(RegExp(r'^package:'), '');
    return '$owner${fn is FuncRef ? fn.name : fn.toString()} [$url]';
  }

  String pct(final int n) =>
      '${(n * 100 / count).toStringAsFixed(1).padLeft(5)}%';
  stdout.writeln(
    'samples in window: $count over ${window}s '
    '(period ${samples.samplePeriod} us)',
  );
  stdout.writeln('\nby vm tag:');
  for (final e in _sorted(tags).take(top)) {
    stdout.writeln('  ${pct(e.value)}  ${e.key}');
  }
  stdout.writeln('\ntop exclusive:');
  for (final e in _sorted(exclusive).take(top)) {
    stdout.writeln('  ${pct(e.value)}  ${name(e.key)}');
  }
  stdout.writeln('\ntop inclusive:');
  for (final e in _sorted(inclusive).take(top)) {
    stdout.writeln('  ${pct(e.value)}  ${name(e.key)}');
  }
}

List<MapEntry<K, int>> _sorted<K>(final Map<K, int> counts) =>
    counts.entries.toList()..sort((final a, final b) => b.value - a.value);

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
