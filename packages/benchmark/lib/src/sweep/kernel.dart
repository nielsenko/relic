import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../browser_headers.dart';
import '../cpu.dart';
import 'kernel_report.dart';
import 'net.dart';
import 'processes.dart';

/// What a kernel run measures with. Each setting is also an environment
/// variable of the same name in capitals.
final class KernelSettings {
  /// The output directory.
  final Directory out;

  /// Seconds of each load window.
  final int window;

  /// Worker threads of oha.
  final int ohaThreads;

  /// The servers to run, all when empty. A name matches with or without
  /// its `@<sdk>` suffix.
  final Set<String> only;

  /// `lo` or `veth`, see [Net].
  final String net;

  /// NAPI threads at each end of the veth pair, or null for the default.
  final int? vethQueues;

  /// The SDKs every Dart server runs on, by label, in order.
  final Map<String, String> dartSdks;

  /// What the library window samples, one user instruction in
  /// [samplePeriod] by default. Without a PMU it can be `cpu-clock:u`, for
  /// the function names alone.
  final String sampleEvent;
  final int samplePeriod;

  KernelSettings({
    required this.out,
    required this.window,
    required this.ohaThreads,
    required this.only,
    required this.net,
    required this.vethQueues,
    required this.dartSdks,
    required this.sampleEvent,
    required this.samplePeriod,
  });
}

/// What perf counts by name: the calls a server makes per request, those
/// this kernel has. All of syscalls:sys_enter_* would be a descriptor per
/// event and thread.
const _calls = [
  'read', 'write', 'readv', 'writev', 'recvfrom', 'sendto', 'recvmsg', //
  'sendmsg', 'epoll_wait', 'epoll_pwait', 'epoll_pwait2', 'epoll_ctl',
  'io_uring_enter', 'futex', 'ioctl', 'mmap', 'munmap', 'madvise',
  'mprotect', 'nanosleep', 'clock_nanosleep', 'sched_yield', 'poll',
  'ppoll', 'accept4', 'close', 'fcntl', 'getsockopt', 'setsockopt',
  'shutdown',
];

/// Instructions and cycles need a PMU in the VM. On GCP that is C4, C4A
/// and M4 created with --performance-monitoring-unit, and not C4D.
const _counters = 'instructions:u,instructions:k,cycles:u,cycles:k';

const _port = 18098;

/// The kernel's share of a request. For each server, on one isolate or
/// thread, and for the plaintext and headers workloads, the run reads the
/// server's user and system time from /proc over a load window. It then
/// counts the server's system calls by name over two more windows, one
/// with perf's syscall tracepoints and one with strace, each when it may.
/// Where the VM has a PMU, one more window counts instructions and cycles
/// in user and kernel mode, and another samples the user instructions to
/// split them by library and function. The Dart servers then write a perf
/// map, which names their JIT code. Linux only.
///
/// The baselines must be built first, as for the sweep. perf runs through
/// `sudo -n` when sudo allows it, and strace attaches as the user, which
/// takes kernel.yama.ptrace_scope 0. The GCP startup script arranges both.
///
/// With [KernelSettings.dartSdks] each Dart server runs once per SDK, one
/// right after the other, as in the sweep. Each SDK gets a copy of the
/// repository beside this one, and its label follows an @ in the server's
/// name, such as relic-io@3.14.0. hyper and dusty run once.
///
/// Over veth the server's NAPI threads take its share of the network
/// stack: their ticks follow the server's in ticks.txt, and the PMU window
/// counts them with the server.
final class Kernel {
  final KernelSettings settings;

  /// The directory of this package.
  final String package;

  late final Net net;
  late final List<
    ({String label, String package, Map<String, String> environment})
  >
  _sdks;
  late final List<String> _sudo;
  late final List<String> _oha;
  late final String _events;
  late final bool _perfOk;
  late final bool _counted;
  late final bool _sampled;
  late final bool _strace;

  Kernel(this.settings, this.package);

  String get _out => settings.out.path;
  String get _url => 'http://${net.host}:$_port';
  File _file(String name) => File(p.join(_out, name));
  void _progress(String line) =>
      _file('progress.log').writeAsStringSync('$line\n', mode: FileMode.append);
  void _machine(String line) =>
      _file('machine.txt').writeAsStringSync('$line\n', mode: FileMode.append);

  /// The browser head of lib/src/browser_headers.dart, as oha arguments.
  static final List<String> _browserHead = [
    for (final header in browserHeaders) ...['-H', header],
  ];

  Future<int> run() async {
    if (!Platform.isLinux) {
      stderr.writeln('The kernel run reads /proc and needs Linux.');
      return 1;
    }
    settings.out.createSync(recursive: true);
    net = await Net.create(settings.net, queues: settings.vethQueues);
    final signals = [
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
        signal.watch().listen((_) async {
          await net.teardown();
          exit(130);
        }),
    ];
    try {
      if (!await net.setup(_file('net.txt'))) {
        final message = 'no veth path, see ${_file('net.txt').path}';
        stdout.writeln(message);
        _progress(message);
        return 1;
      }
      // perf opens one descriptor per event and thread.
      raiseOpenFileLimit(65536);
      _sudo = await succeeds(['sudo', '-n', 'perf', '--version'])
          ? const ['sudo', '-n']
          : const [];
      _selectSdks();
      final first = _sdks.first.environment;
      final oha = which('oha', environment: first) ?? 'oha';
      _oha = net.clientSide([oha], first);
      await _prepareSdks();
      await _writeMachine();
      await _probePerf();

      // Relic 1.2.0 runs from its own package configuration, not this
      // package's, which holds the relic of this tree.
      const old = 'baselines/relic_1_2';
      await _dartServer('dartio', [
        'dart',
        'baselines/dartio/server.dart',
        '$_port',
      ]);
      await _dartServer('relic12-io', [
        'dart',
        '--packages=$old/.dart_tool/package_config.json',
        '$old/bin/server.dart',
        '$_port',
        '1',
      ]);
      for (final (name, kind) in const [
        ('relic-io', 'io'),
        ('shelf', 'shelf'),
        ('relic-native', 'native'),
      ]) {
        await _dartServer(name, [
          'dart',
          'run',
          'bin/load_serve.dart',
          kind,
          '1',
        ]);
      }
      final sdk = _sdks.first;
      await _server('hyper', [
        p.join(package, 'baselines/hyper/target/release/relic_baseline_hyper'),
        '$_port',
        '1',
      ], sdk);
      await _server('dusty', [
        p.join(package, 'baselines/dusty/zig-out/bin/relic_baseline_dusty'),
        '$_port',
        '1',
      ], sdk);
      try {
        _file('kernel.md').writeAsStringSync(kernelReport(settings.out));
        _file('kernel_rows.err').writeAsStringSync('');
      } on Exception catch (e, stack) {
        _file('kernel_rows.err').writeAsStringSync('$e\n$stack\n');
      }
      _progress('done ${DateTime.now()}');
      return 0;
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
      await net.teardown();
    }
  }

  void _selectSdks() {
    final base = Map<String, String>.of(Platform.environment);
    if (settings.dartSdks.isEmpty) {
      _sdks = [(label: '', package: package, environment: base)];
      return;
    }
    final repository = p.normalize(p.join(package, '..', '..'));
    _sdks = [
      for (final MapEntry(key: label, value: sdk) in settings.dartSdks.entries)
        (
          label: label,
          package: p.join('$repository-dart-$label', 'packages', 'benchmark'),
          environment: {
            ...base,
            'PATH': '${p.join(sdk, 'bin')}:${base['PATH'] ?? ''}',
          },
        ),
    ];
  }

  Future<void> _prepareSdks() async {
    final repository = p.normalize(p.join(package, '..', '..'));
    for (final (i, sdk) in _sdks.indexed) {
      final suffix = sdk.label.isEmpty ? '' : '-${sdk.label}';
      if (sdk.package != package) {
        final from = i > 0
            ? p.normalize(p.join(_sdks.first.package, '..', '..'))
            : repository;
        await runLogged([
          'rsync',
          '-a',
          '--delete',
          for (final name in const [
            '.git',
            '.jj',
            '.dart_tool',
            'build',
            'target',
            'zig-out',
            '.zig-cache',
            'zig-pkg',
            'sweep-out',
            'kernel-out',
          ])
            '--exclude=$name',
          '$from/',
          '${p.normalize(p.join(sdk.package, '..', '..'))}/',
        ], stdoutFile: _file('rsync$suffix.log'));
        await runLogged(
          ['dart', 'pub', 'get'],
          stdoutFile: _file('pub$suffix.log'),
          environment: sdk.environment,
          workingDirectory: sdk.package,
        );
      }
      await runLogged(
        ['dart', 'pub', 'get'],
        stdoutFile: _file('relic_1_2_pub$suffix.log'),
        environment: sdk.environment,
        workingDirectory: p.join(sdk.package, 'baselines', 'relic_1_2'),
      );
      // Runs the build hooks for `dart run` here, since the server side
      // of veth has no route to the hooks' downloads.
      await runLogged(
        ['dart', 'run', 'bin/http_load.dart', '--help'],
        stdoutFile: _file('jit_build$suffix.log'),
        environment: sdk.environment,
        workingDirectory: sdk.package,
      );
    }
  }

  Future<void> _writeMachine() async {
    final first = _sdks.first.environment;
    Future<String> firstLine(List<String> command) async => (await outputOf(
      command,
      environment: first,
      mergeStderr: true,
    )).split('\n').first;
    String kernelSetting(String path) {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync().trim() : '';
    }

    final model = File(
      '/proc/cpuinfo',
    ).readAsLinesSync().where((line) => line.contains('model name'));
    final lines = [
      'machine: ${await outputOf(['uname', '-a'])}',
      if (model.isNotEmpty) model.first,
      'cores: ${await outputOf(['nproc'])}',
      for (final sdk in _sdks)
        'dart${sdk.label.isEmpty ? '' : ' ${sdk.label}'}: '
            '${await outputOf(['dart', '--version'], environment: sdk.environment, mergeStderr: true)}',
      'oha: ${await outputOf(['oha', '--version'], environment: first, mergeStderr: true)}',
      'perf: ${await firstLine([..._sudo, 'perf', '--version'])}',
      'strace: ${await firstLine(['strace', '-V'])}',
      'clock ticks: ${await outputOf(['getconf', 'CLK_TCK'])}',
      'window: ${settings.window}',
      'load: oha, 64 connections, ${settings.ohaThreads} threads, '
          '${_browserHead.length} header arguments for headers',
      'ptrace_scope: ${kernelSetting('/proc/sys/kernel/yama/ptrace_scope')}',
      'perf_event_paranoid: '
          '${kernelSetting('/proc/sys/kernel/perf_event_paranoid')}',
      'io_uring_disabled: '
          '${kernelSetting('/proc/sys/kernel/io_uring_disabled')}',
      'net: ${net.kind}',
      if (net.isVeth) _file('net.txt').readAsLinesSync().first,
    ];
    _file('machine.txt').writeAsStringSync(lines.map((l) => '$l\n').join());
  }

  /// Finds what perf may do here: count the syscall tracepoints, count the
  /// PMU and sample.
  Future<void> _probePerf() async {
    final available = RegExp(r'syscalls:sys_enter_[a-z0-9_]+')
        .allMatches(
          await outputOf([..._sudo, 'perf', 'list', 'syscalls:sys_enter_*']),
        )
        .map((m) => m.group(0)!)
        .toSet();
    _events = [
      'raw_syscalls:sys_enter',
      for (final call in _calls)
        if (available.contains('syscalls:sys_enter_$call'))
          'syscalls:sys_enter_$call',
    ].join(',');
    _machine('perf events: $_events');
    _perfOk = await succeeds([
      ..._sudo,
      'perf',
      'stat',
      '-e',
      _events,
      '--',
      'true',
    ]);
    final counted = await outputOf([
      ..._sudo,
      'perf',
      'stat',
      '-x,',
      '-e',
      _counters,
      '--',
      'true',
    ], mergeStderr: true);
    _counted = RegExp(
      r'^[0-9]+,[^,]*,instructions:k',
      multiLine: true,
    ).hasMatch(counted);
    _machine('counters: ${_counted ? 1 : 0}');
    final probe = _file('probe.data').path;
    _sampled = await succeeds([
      ..._sudo,
      'perf',
      'record',
      '-q',
      '-e',
      settings.sampleEvent,
      '-o',
      probe,
      '--',
      'true',
    ]);
    await succeeds([..._sudo, 'rm', '-f', probe]);
    _machine(
      'sampled: ${_sampled ? 1 : 0}, ${settings.sampleEvent} every '
      '${settings.samplePeriod}',
    );
    _strace = which('strace') != null;
  }

  bool _wanted(String name) {
    if (settings.only.isEmpty) return true;
    final at = name.indexOf('@');
    return settings.only.contains(name) ||
        (at > 0 && settings.only.contains(name.substring(0, at)));
  }

  /// The pid listening on the port where the servers run, or null.
  Future<int?> _listener() async {
    final sockets = await outputOf(
      net.isVeth
          ? net.inNamespace('srv', ['ss', '-ltnpH', 'sport = :$_port'])
          : ['ss', '-ltnpH', 'sport = :$_port'],
    );
    final pid = RegExp(r'pid=(\d+)').firstMatch(sockets)?.group(1);
    return pid == null ? null : int.parse(pid);
  }

  Future<void> _stop(Process launcher) async {
    await killTree(launcher.pid);
    for (var i = 0; i < 10; i++) {
      final left = await _listener();
      if (left == null) break;
      Process.killPid(left);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// The oha command for one window of [seconds] on [route].
  List<String> _ohaFor(String route, int seconds) => [
    ..._oha,
    '--no-tui',
    '--output-format',
    'json',
    '-c',
    '64',
    '-z',
    '${seconds}s',
    '--worker-threads',
    '${settings.ohaThreads}',
    if (route == 'headers') ..._browserHead,
    '$_url/$route',
  ];

  /// Runs each Dart server once per SDK, from the SDK's copy of this
  /// package, with the VM's perf map flag after the command's first dart
  /// where the window samples.
  Future<void> _dartServer(String name, List<String> command) async {
    final flagged = [...command];
    if (_sampled) {
      flagged.insert(
        flagged.indexOf('dart') + 1,
        '--generate-perf-events-symbols',
      );
    }
    for (final sdk in _sdks) {
      await _server(
        '$name${sdk.label.isEmpty ? '' : '@${sdk.label}'}',
        flagged,
        sdk,
      );
    }
  }

  /// Measures both workloads on one server.
  Future<void> _server(
    String name,
    List<String> command,
    ({String label, String package, Map<String, String> environment}) sdk,
  ) async {
    if (!_wanted(name)) return;
    final environment = sdk.environment;
    final launcher = await startLogged(
      net.serverSide(command, environment),
      _file('$name.server.log'),
      environment: environment,
      workingDirectory: sdk.package,
      nohup: true,
    );
    var up = false;
    for (var i = 0; i < 600 && !up; i++) {
      up = await succeeds(
        net.clientSide([
          'curl',
          '-s',
          '-o',
          '/dev/null',
          '$_url/plaintext',
        ], environment),
        environment: environment,
      );
      if (!up) await Future<void>.delayed(const Duration(seconds: 1));
    }
    final pid = up ? await _listener() : null;
    if (pid == null) {
      _progress('$name not up');
      await _stop(launcher);
      return;
    }
    final napiDevice = net.napiDevice;
    // The PMU window counts the server's NAPI threads with it.
    final counted = [
      pid,
      if (napiDevice != null) ...napiThreads(napiDevice),
    ].join(',');
    String ticks() {
      final used = ticksOf('/proc/$pid/stat');
      return used == null ? '0 0' : '${used.$1} ${used.$2}';
    }

    Future<int> window(
      List<String> command,
      String stem, {
      String output = 'json',
    }) => runLogged(
      command,
      stdoutFile: _file('$name.$stem.$output'),
      stderrFile: _file('$name.$stem.err'),
      environment: environment,
    );
    for (final route in const ['plaintext', 'headers']) {
      await Process.run(
        _ohaFor(route, 5).first,
        _ohaFor(route, 5).sublist(1),
        environment: environment,
      );
      final oha = _ohaFor(route, settings.window);
      final before = ticks();
      final napiBefore = napiDevice == null ? '' : ' ${net.napiTicks()}';
      await runLogged(
        oha,
        stdoutFile: _file('$name.$route.time.json'),
        passStderr: true,
        environment: environment,
      );
      final after = ticks();
      final napiAfter = napiDevice == null ? '' : ' ${net.napiTicks()}';
      _file('ticks.txt').writeAsStringSync(
        '$name $route $pid $before $after$napiBefore$napiAfter\n',
        mode: FileMode.append,
      );
      if (_counted) {
        await window([
          ..._sudo,
          'perf',
          'stat',
          '--per-thread',
          '-x,',
          '-e',
          _counters,
          '-p',
          counted,
          '-o',
          _file('$name.$route.counters.csv').path,
          '--',
          ...oha,
        ], '$route.counters');
      }
      if (_sampled) {
        await _sample(name, route, pid, oha, environment);
      }
      if (_perfOk) {
        await window([
          ..._sudo,
          'perf',
          'stat',
          '--per-thread',
          '-x,',
          '-e',
          _events,
          '-p',
          '$pid',
          '-o',
          _file('$name.$route.perf.csv').path,
          '--',
          ...oha,
        ], '$route.perf');
      }
      if (_strace) {
        final tracer = await startLogged([
          'strace',
          '-f',
          '-c',
          '-q',
          '-p',
          '$pid',
          '-o',
          _file('$name.$route.strace.txt').path,
        ], _file('$name.$route.strace.err'));
        await Future<void>.delayed(const Duration(seconds: 2));
        await runLogged(
          oha,
          stdoutFile: _file('$name.$route.strace.json'),
          passStderr: true,
          environment: environment,
        );
        tracer.kill(ProcessSignal.sigint);
        await tracer.exitCode;
      }
    }
    _progress('$name done ${DateTime.now()}');
    await _stop(launcher);
  }

  /// Samples the server's user instructions over one window and splits
  /// them by library and by function.
  Future<void> _sample(
    String name,
    String route,
    int pid,
    List<String> oha,
    Map<String, String> environment,
  ) async {
    final stem = '$name.$route';
    final data = _file('$stem.record.data').path;
    final errors = _file('$stem.record.err');
    await runLogged(
      [
        ..._sudo,
        'perf',
        'record',
        '-q',
        '-e',
        settings.sampleEvent,
        '-c',
        '${settings.samplePeriod}',
        '-p',
        '$pid',
        '-o',
        data,
        '--',
        ...oha,
      ],
      stdoutFile: _file('$stem.record.json'),
      stderrFile: errors,
      environment: environment,
    );
    void note(Object? text) =>
        errors.writeAsStringSync('$text', mode: FileMode.append);
    final report = await _perf([
      'report',
      '-i',
      data,
      '--stdio',
      '-q',
      '--sort',
      'dso',
    ]);
    _file('$stem.dso.txt').writeAsStringSync(report.stdout as String);
    note(report.stderr);
    // The server's perf map lies in /tmp, which the namespaces share.
    final map = File('/tmp/perf-$pid.map');
    final copy = _file('$stem.perf.map');
    if (map.existsSync()) {
      map.copySync(copy.path);
    } else {
      note('no ${map.path}\n');
    }
    final script = await _perf(['script', '-i', data, '-F', 'ip,sym,dso']);
    note(script.stderr);
    _file('$stem.sym.txt').writeAsStringSync(
      perfSymbols(
        const LineSplitter().convert(script.stdout as String),
        perfMap: copy,
      ),
    );
    await succeeds([..._sudo, 'rm', '-f', data]);
  }

  Future<ProcessResult> _perf(List<String> arguments) {
    final command = [..._sudo, 'perf', ...arguments];
    return Process.run(command.first, command.sublist(1));
  }
}
