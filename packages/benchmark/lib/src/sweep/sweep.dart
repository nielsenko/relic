import 'dart:async';
import 'dart:io';

import 'package:bench_press/bench_press.dart';
import 'package:path/path.dart' as p;

import 'net.dart';
import 'processes.dart';
import 'targets.dart';

/// What a sweep runs with. Each setting is also an environment variable of
/// the same name in capitals, as the shell script this replaces took them.
final class SweepSettings {
  /// The output directory.
  final Directory out;

  /// The http_load arguments of every HTTP target.
  final List<String> load;

  /// Whether to wait for a one-minute load average under 1.5 before every
  /// target, up to 15 minutes.
  final bool quiet;

  /// Seconds to wait after a target.
  final int pause;

  /// The targets to run, all when empty.
  final Set<String> only;

  /// Whether to record the CPU time of every thread through each target's
  /// run, in `<target>.threads.txt`. Linux only.
  final bool sample;

  /// `lo` or `veth`, see [Net].
  final String net;

  /// NAPI threads at each end of the veth pair, or null for the default.
  final int? vethQueues;

  /// The SDKs every Dart target runs on, by label, in order. Empty runs
  /// them once on the dart of PATH.
  final Map<String, String> dartSdks;

  /// The variants of this repository every Dart target runs on, each a
  /// patch file by label, in order. An empty patch is the repository as it
  /// is. Not together with [dartSdks].
  final Map<String, String> variants;

  /// Worker threads of oha and of the WebSocket load client.
  final int ohaThreads;

  /// Whether the sweep stops before the first target when the machine
  /// gives no hardware counters.
  final bool requirePmu;

  final int wsConnections;
  final int wsSeconds;
  final int wsWarmup;
  final int wsIdle;

  SweepSettings({
    required this.out,
    required this.load,
    required this.quiet,
    required this.pause,
    required this.only,
    required this.sample,
    required this.net,
    required this.vethQueues,
    required this.dartSdks,
    required this.variants,
    required this.ohaThreads,
    this.requirePmu = false,
    required this.wsConnections,
    required this.wsSeconds,
    required this.wsWarmup,
    required this.wsIdle,
  });

  /// `<label>=<value>` pairs separated by spaces, as DART_SDKS lists SDK
  /// directories and VARIANTS lists patch files.
  static Map<String, String> parseSdks(String pairs) => {
    for (final pair in pairs.split(RegExp(r'\s+')))
      if (pair.contains('='))
        pair.substring(0, pair.indexOf('=')): pair.substring(
          pair.indexOf('=') + 1,
        ),
  };
}

/// A Dart SDK, or a variant of this repository, the Dart targets run on.
final class Sdk {
  /// Its label, empty for the dart of PATH on the repository as it is.
  final String label;

  /// `dart` for an SDK and `variant` for a patched repository.
  final String kind;

  /// The patch its copy of the repository takes, empty for none.
  final String patch;

  /// Its copy of this package.
  final String package;

  /// Where its results go.
  final Directory out;

  /// The environment of what runs on it, its dart first in PATH.
  final Map<String, String> environment;

  Sdk(
    this.label,
    this.package,
    this.out,
    this.environment, {
    this.kind = 'dart',
    this.patch = '',
  });

  /// ` dart-<label>` or ` variant-<label>` after a target's name in the
  /// progress log.
  String get suffix => label.isEmpty ? '' : ' $kind-$label';
}

/// The machine's one-minute load average.
Future<double> loadAverage() async {
  final file = File('/proc/loadavg');
  if (file.existsSync()) {
    return double.parse(file.readAsStringSync().split(' ').first);
  }
  // `{ 2.65 3.70 4.26 }`
  final text = await outputOf(['sysctl', '-n', 'vm.loadavg']);
  return double.tryParse(text.split(RegExp(r'\s+')).elementAtOrNull(1) ?? '') ??
      0;
}

/// The machine's CPU count: every CPU on Linux, the physical ones on macOS.
Future<int> cpuCount() async => int.parse(
  File('/proc/cpuinfo').existsSync()
      ? await outputOf(['nproc'])
      : await outputOf(['sysctl', '-n', 'hw.physicalcpu']),
);

/// The command that runs [arguments] on this program again: the Dart
/// script on the VM that runs this one, or the compiled executable.
///
/// Not `dart run`, which checks the build hooks first and writes its
/// progress to the output.
List<String> selfCommand(List<String> arguments) {
  final script = Platform.script.toFilePath();
  return script.endsWith('.dart')
      ? [Platform.resolvedExecutable, script, ...arguments]
      : [Platform.resolvedExecutable, ...arguments];
}

/// The load sweep: one http_load run per target, each against a server
/// started for it alone in a process of its own, with the results of every
/// target in its own files under the output directory. The WebSocket
/// targets come last.
///
/// The eight-way targets run on 16 cores or more, over veth when the
/// servers get 8 CPUs or more, or when named in [SweepSettings.only]. The baselines must be built first, see the
/// comments at the top of baselines/*/.
///
/// With [SweepSettings.dartSdks] every Dart target runs once per SDK, one
/// right after the other, to compare them. Each SDK gets a copy of the
/// repository beside this one, `<repository>-dart-<label>`, with a package
/// configuration, build hooks and AOT bundle of its own. The first SDK
/// resolves the packages and the others take its lock files. Its results
/// go to `<out>/dart-<label>`. A target that is not Dart runs once, with
/// its results in the output directory.
///
/// With [SweepSettings.variants] every Dart target runs once per variant
/// of this repository, on the dart of PATH, to compare changes to Relic.
/// Each variant gets a copy of the repository,
/// `<repository>-variant-<label>`, with its patch applied, and its results
/// go to `<out>/variant-<label>`.
final class Sweep {
  final SweepSettings settings;

  /// The directory of this package.
  final String package;

  /// The test certificates of relic_native.
  final String certs;

  late final Net net;
  late final List<Sdk> _sdks;
  late final int _cores;
  late final File _progress;
  Process? _sampler;

  Sweep(this.settings, this.package)
    : certs = p.normalize(
        p.join(package, '..', 'relic_native', 'test', 'certs'),
      );

  String get _out => settings.out.path;
  String get _hyper =>
      p.join(package, 'baselines/hyper/target/release/relic_baseline_hyper');
  String get _dusty =>
      p.join(package, 'baselines/dusty/zig-out/bin/relic_baseline_dusty');
  String _tungstenite(String binary) =>
      p.join(package, 'baselines/tungstenite/target/release', binary);
  List<String> get _pair => [
    p.join(certs, 'localhost_cert.pem'),
    p.join(certs, 'localhost_key.pem'),
  ];

  void _log(String line) {
    stdout.writeln(line);
    _progress.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  /// Runs the sweep and returns its exit code.
  Future<int> run() async {
    settings.out.createSync(recursive: true);
    _progress = File(p.join(_out, 'progress.log'));
    net = await Net.create(settings.net, queues: settings.vethQueues);
    final signals = [
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
        signal.watch().listen((_) async {
          await _unsample();
          await net.teardown();
          exit(130);
        }),
    ];
    try {
      if (!await net.setup(File(p.join(_out, 'net.txt')))) {
        _log('no veth path, see ${p.join(_out, 'net.txt')}');
        return 1;
      }
      if (settings.dartSdks.isNotEmpty && settings.variants.isNotEmpty) {
        _log('DART_SDKS and VARIANTS cannot be combined');
        return 1;
      }
      _cores = await cpuCount();
      _sdks = _selectSdks();
      final (pmu, why) = _probePmu();
      await _writeMachine(pmu ? 'yes' : 'no, $why');
      if (settings.requirePmu && !pmu) {
        _log('no hardware counters: $why');
        return 1;
      }
      if (!await _prepareSdks()) return 1;
      _progress.writeAsStringSync(
        'start ${DateTime.now()}\n',
        mode: FileMode.append,
      );
      for (final target in httpTargets) {
        await _eachSdk(
          target.name,
          dart: target.launch.isDart,
          (sdk, out, suffix) => _httpRun(target, sdk, out, suffix),
        );
      }
      await _webSockets();
      _progress.writeAsStringSync(
        'done ${DateTime.now()}\n',
        mode: FileMode.append,
      );
      return 0;
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
      await net.teardown();
    }
  }

  /// The SDKs the Dart targets run on. Each has its dart first in PATH,
  /// the certificates of the servers and, over veth, the oha of the client
  /// side in its environment.
  List<Sdk> _selectSdks() {
    final base = {...Platform.environment, 'RELIC_TEST_CERTS': certs};
    final oha = net.ohaCommand(base);
    if (oha != null) base['BENCH_OHA'] = oha;
    final repository = p.normalize(p.join(package, '..', '..'));
    if (settings.variants.isNotEmpty) {
      return [
        for (final MapEntry(key: label, value: patch)
            in settings.variants.entries)
          Sdk(
            label,
            p.join('$repository-variant-$label', 'packages', 'benchmark'),
            Directory(p.join(_out, 'variant-$label')),
            base,
            kind: 'variant',
            patch: patch,
          ),
      ];
    }
    if (settings.dartSdks.isEmpty) {
      return [Sdk('', package, settings.out, base)];
    }
    return [
      for (final MapEntry(key: label, value: sdk) in settings.dartSdks.entries)
        Sdk(
          label,
          p.join('$repository-dart-$label', 'packages', 'benchmark'),
          Directory(p.join(_out, 'dart-$label')),
          {...base, 'PATH': '${p.join(sdk, 'bin')}:${base['PATH'] ?? ''}'},
        ),
    ];
  }

  /// Whether this process can read its own instructions and cycles, in
  /// user and kernel mode, as http_load reads a server's, and why not.
  (bool, String) _probePmu() {
    var why = '';
    final counters = PerfCounters.open(
      pids: [pid],
      kernel: true,
      onUnavailable: (reason) => why = reason,
    );
    if (counters == null) return (false, why);
    final modes = counters.modes;
    counters.close();
    return (true, modes);
  }

  Future<void> _writeMachine(String pmu) async {
    final first = _sdks.first.environment;
    Future<String> version(
      List<String> command, {
      bool firstLine = false,
    }) async {
      final text = await outputOf(
        command,
        environment: first,
        mergeStderr: true,
      );
      return firstLine ? text.split('\n').first : text;
    }

    final lines = [
      'machine: ${await outputOf(['uname', '-a'])}',
    ];
    final cpuinfo = File('/proc/cpuinfo');
    if (cpuinfo.existsSync()) {
      final model = cpuinfo.readAsLinesSync().where(
        (line) => line.contains('model name'),
      );
      if (model.isNotEmpty) lines.add(model.first);
      lines.add('cores: ${await outputOf(['nproc'])}');
    } else {
      lines.add(
        'cpu: '
        '${await outputOf(['sysctl', '-n', 'machdep.cpu.brand_string'])}, '
        'cores: ${await outputOf(['sysctl', '-n', 'hw.physicalcpu'])}',
      );
    }
    for (final sdk in _sdks) {
      final dart = await outputOf(
        ['dart', '--version'],
        environment: sdk.environment,
        mergeStderr: true,
      );
      lines.add('dart${sdk.label.isEmpty ? '' : ' ${sdk.label}'}: $dart');
      if (sdk.patch.isNotEmpty) lines.add('patch ${sdk.label}: ${sdk.patch}');
    }
    final paranoid = File('/proc/sys/kernel/perf_event_paranoid');
    lines
      ..add('oha: ${await version(['oha', '--version'])}')
      ..add(
        'zig: '
        '${await outputOf(['zig', 'version'], environment: first, workingDirectory: p.join(package, '..', 'relic_native'), mergeStderr: true)}',
      )
      ..add('rustc: ${await version(['rustc', '--version'])}')
      ..add('deno: ${await version(['deno', '--version'], firstLine: true)}')
      ..add('bun: ${await version(['bun', '--version'], firstLine: true)}')
      ..add('load: ${settings.load.join(' ')}')
      ..add(
        'perf_event_paranoid: '
        '${paranoid.existsSync() ? paranoid.readAsStringSync().trim() : ''}',
      )
      ..add('pmu: $pmu')
      ..add('net: ${net.kind}');
    if (net.isVeth) {
      lines.add(File(p.join(_out, 'net.txt')).readAsLinesSync().first);
    }
    File(
      p.join(_out, 'machine.txt'),
    ).writeAsStringSync(lines.map((l) => '$l\n').join());
  }

  /// Copies the repository for every SDK but the dart of PATH and for every
  /// variant, patches a variant's copy, resolves the packages, and builds
  /// the AOT bundle and the hooks of `dart run` on each. Returns false when
  /// a patch does not apply.
  Future<bool> _prepareSdks() async {
    final repository = p.normalize(p.join(package, '..', '..'));
    for (final (i, sdk) in _sdks.indexed) {
      sdk.out.createSync(recursive: true);
      File log(String name) => File(p.join(sdk.out.path, name));
      if (sdk.package != package) {
        // The SDKs after the first take the first one's lock files. A
        // variant starts from the repository as it is.
        final from = i > 0 && sdk.kind == 'dart'
            ? p.normalize(p.join(_sdks.first.package, '..', '..'))
            : repository;
        final copy = p.normalize(p.join(sdk.package, '..', '..'));
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
          ])
            '--exclude=$name',
          '$from/',
          '$copy/',
        ], stdoutFile: log('rsync.log'));
        if (sdk.patch.isNotEmpty &&
            await runLogged(
                  ['git', 'apply', sdk.patch],
                  stdoutFile: log('patch.log'),
                  workingDirectory: copy,
                ) !=
                0) {
          _log(
            'variant ${sdk.label}: patch does not apply, see '
            '${log('patch.log').path}',
          );
          return false;
        }
        await runLogged(
          ['dart', 'pub', 'get'],
          stdoutFile: log('pub.log'),
          environment: sdk.environment,
          workingDirectory: sdk.package,
        );
      }
      await runLogged(
        ['dart', 'build', 'cli', '--target', 'bin/load_serve.dart'],
        stdoutFile: log('aot_build.log'),
        environment: sdk.environment,
        workingDirectory: sdk.package,
      );
      // Runs the build hooks for `dart run` before the first server needs
      // them.
      await runLogged(
        ['dart', 'run', 'bin/http_load.dart', '--help'],
        stdoutFile: log('jit_build.log'),
        environment: sdk.environment,
        workingDirectory: sdk.package,
      );
      await runLogged(
        ['dart', 'pub', 'get'],
        stdoutFile: log('relic_1_2_pub.log'),
        environment: sdk.environment,
        workingDirectory: p.join(sdk.package, 'baselines', 'relic_1_2'),
      );
    }
    return true;
  }

  bool _wanted(String name) {
    if (settings.only.isEmpty) {
      final roomFor8 = net.isVeth ? net.serverCpuCount >= 8 : _cores >= 16;
      return roomFor8 || !RegExp(r'[a-z]8(-|$)').hasMatch(name);
    }
    return settings.only.contains(name);
  }

  /// Runs a target on every SDK when it is [dart], or once on the first
  /// SDK with its results in the output directory.
  Future<void> _eachSdk(
    String name,
    Future<void> Function(Sdk sdk, Directory out, String suffix) run, {
    required bool dart,
  }) async {
    if (!_wanted(name)) return;
    if (!dart) return run(_sdks.first, settings.out, '');
    for (final sdk in _sdks) {
      await run(sdk, sdk.out, sdk.suffix);
    }
  }

  Future<void> _quiet() async {
    if (!settings.quiet) return;
    for (var i = 0; i < 90; i++) {
      if (await loadAverage() < 1.5) return;
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }

  /// The processes listening on TCP [port] where the servers run.
  Future<List<int>> _listeners(int port) async {
    final String pids;
    if (net.isVeth || which('lsof') == null) {
      final sockets = await outputOf(
        net.isVeth
            ? net.inNamespace('srv', ['ss', '-ltnpH', 'sport = :$port'])
            : ['ss', '-ltnpH', 'sport = :$port'],
      );
      pids = RegExp(
        r'pid=(\d+)',
      ).allMatches(sockets).map((m) => m.group(1)!).join('\n');
    } else {
      pids = await outputOf([
        'lsof',
        '-nP',
        '-iTCP:$port',
        '-sTCP:LISTEN',
        '-t',
      ]);
    }
    return {
      for (final pid in pids.split('\n')) ?int.tryParse(pid.trim()),
    }.toList();
  }

  /// Stops the server started as [process] and whoever still listens on
  /// [port] after it.
  Future<void> _stop(Process process, int port) async {
    await killTree(process.pid);
    for (var i = 0; i < 10; i++) {
      final left = await _listeners(port);
      if (left.isEmpty) break;
      left.forEach(Process.killPid);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Starts the thread sampler into [file].
  Future<void> _sample(File file) async {
    if (!settings.sample || !File('/proc/stat').existsSync()) return;
    _sampler = await startLogged([
      if (net.isVeth) ...['taskset', '-c', net.clientCpus],
      ...selfCommand(const ['threads']),
    ], file);
  }

  Future<void> _unsample() async {
    final sampler = _sampler;
    if (sampler == null) return;
    _sampler = null;
    await killTree(sampler.pid);
    await sampler.exitCode;
  }

  /// The command of [target]'s server on [sdk], and the directory it
  /// starts in when that matters.
  (List<String>, String?) _server(HttpTarget target, Sdk sdk) {
    final port = '${target.port}';
    final ways = '${target.ways}';
    final pair = target.tls ? _pair : const <String>[];
    final served = [target.kind, ways, target.tls ? 'tls' : 'notls', port];
    switch (target.launch) {
      case Launch.hyper:
        return ([_hyper, port, ways, ...pair], null);
      case Launch.dusty:
        return ([_dusty, port, ways, ...pair], null);
      case Launch.deno:
        return (
          [
            'deno',
            'run',
            '--allow-net',
            '--allow-env=BENCH_ADDRESS',
            if (target.tls) '--allow-read',
            p.join(package, 'baselines/deno/server.mjs'),
            port,
            ...pair,
          ],
          null,
        );
      case Launch.bun:
        return (
          [
            'bun',
            'run',
            p.join(package, 'baselines/bun/server.mjs'),
            port,
            ...pair,
          ],
          null,
        );
      case Launch.jit:
        return (['dart', 'run', 'bin/load_serve.dart', ...served], sdk.package);
      case Launch.aot:
        final bundles = Directory(p.join(sdk.package, 'build', 'cli'));
        final binary = [
          if (bundles.existsSync())
            for (final platform in bundles.listSync()..sort(_byPath))
              p.join(platform.path, 'bundle', 'bin', 'load_serve'),
        ].where((path) => File(path).existsSync()).firstOrNull;
        return ([binary ?? 'load_serve', ...served], null);
      case Launch.relic12:
        // Relic 1.2.0 runs from its own package configuration, not this
        // package's, which holds the relic of this tree.
        final old = p.join(sdk.package, 'baselines', 'relic_1_2');
        return (
          [
            'dart',
            '--packages=${p.join(old, '.dart_tool', 'package_config.json')}',
            p.join(old, 'bin', 'server.dart'),
            port,
            ways,
            ...pair,
          ],
          null,
        );
    }
  }

  static int _byPath(FileSystemEntity a, FileSystemEntity b) =>
      a.path.compareTo(b.path);

  Future<void> _httpRun(
    HttpTarget target,
    Sdk sdk,
    Directory out,
    String suffix,
  ) async {
    final name = target.name;
    File file(String extension) => File(p.join(out.path, '$name.$extension'));
    await _quiet();
    final url = target.url(net.host);
    final (command, directory) = _server(target, sdk);
    final server = await startLogged(
      net.serverSide(command, sdk.environment),
      file('server.log'),
      environment: sdk.environment,
      workingDirectory: directory,
      nohup: true,
    );
    await _up('$url/plaintext', sdk);
    final napiDevice = net.napiDevice;
    final packets = net.isVeth ? await net.packets() : 0;
    await _sample(file('threads.txt'));
    final exitCode = await runLogged(
      net.serverSide(
        [
          'dart',
          'run',
          'bin/http_load.dart',
          if (napiDevice != null) '--napi-device=$napiDevice',
          '--targets=$name=$url',
          ...settings.load,
          '--out=${file('md').path}',
        ],
        sdk.environment,
        onServerCpus: false,
      ),
      stdoutFile: file('out'),
      stderrFile: file('err'),
      environment: sdk.environment,
      workingDirectory: sdk.package,
    );
    await _unsample();
    var through = '';
    if (net.isVeth) {
      final taken = await net.packets() - packets;
      through =
          ', $taken packets through NAPI${taken < 1000 ? ', TOO FEW' : ''}';
    }
    _log('$name$suffix exit $exitCode$through');
    await _stop(server, target.port);
    await Future<void>.delayed(Duration(seconds: settings.pause));
  }

  /// Waits until [url] answers on the client side, up to three minutes.
  Future<void> _up(String url, Sdk sdk) async {
    for (var i = 0; i < 180; i++) {
      if (await succeeds(
        net.clientSide([
          'curl',
          '-sk',
          '-o',
          '/dev/null',
          url,
        ], sdk.environment),
        environment: sdk.environment,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    stdout.writeln('$url not up');
  }

  /// The WebSocket targets. Each runs two echo loads, 64-byte text and
  /// 1 KiB binary messages on [SweepSettings.wsConnections] connections
  /// for [SweepSettings.wsSeconds] after [SweepSettings.wsWarmup], and
  /// opens [SweepSettings.wsIdle] quiet connections, all with
  /// baselines/tungstenite's client. The -tls targets run the same over
  /// wss with the test certificates. The results are JSON lines in
  /// `<target>.ws.jsonl`. The URLs name localhost, which the test
  /// certificate covers, and the client connects to the host of [net].
  /// Over veth, `<target>.napi.txt` holds the clock ticks of the server's
  /// NAPI threads and the time before and after each load.
  Future<void> _webSockets() async {
    File(p.join(_out, 'machine.txt')).writeAsStringSync(
      'ws: ${settings.wsConnections} connections, ${settings.wsSeconds} s '
      'after ${settings.wsWarmup} s warm-up, ${settings.wsIdle} idle, '
      '${settings.ohaThreads} client threads\n',
      mode: FileMode.append,
    );
    // The servers hold up to wsIdle sockets each.
    raiseOpenFileLimit(65536);
    for (final tls in const [false, true]) {
      for (final ways in const [1, 2, 4, 8]) {
        final suffix = '${ways == 1 ? '' : ways}-ws${tls ? '-tls' : ''}';
        final scheme = tls ? 'wss' : 'ws';
        final pair = tls ? _pair : const <String>[];
        // The port ends in the way count.
        Future<void> target(
          String name,
          int portPrefix,
          List<String> Function(String port) server, {
          required bool dart,
        }) => _eachSdk(
          '$name$suffix',
          dart: dart,
          (sdk, out, sdkSuffix) => _wsRun(
            '$name$suffix',
            '$scheme://localhost:$portPrefix$ways',
            server('$portPrefix$ways'),
            sdk,
            out,
            sdkSuffix,
          ),
        );

        List<String> Function(String) serve(String kind) =>
            (port) => [
              'dart',
              'run',
              'bin/ws_echo_serve.dart',
              kind,
              port,
              '$ways',
              if (tls) 'tls',
            ];
        await target(
          'tungstenite',
          tls ? 835 : 830,
          (port) => [
            _tungstenite('relic_baseline_ws_echo'),
            port,
            '$ways',
            ...pair,
          ],
          dart: false,
        );
        await target(
          'dusty',
          tls ? 1838 : 1833,
          (port) => [_dusty, port, '$ways', ...pair],
          dart: false,
        );
        await target(
          'relic-native',
          tls ? 1835 : 1830,
          serve('native'),
          dart: true,
        );
        await target('relic-io', tls ? 1836 : 1831, serve('io'), dart: true);
        await target('shelf', tls ? 1837 : 1832, serve('shelf'), dart: true);
      }
    }
  }

  Future<void> _wsRun(
    String name,
    String url,
    List<String> command,
    Sdk sdk,
    Directory out,
    String suffix,
  ) async {
    File file(String extension) => File(p.join(out.path, '$name.$extension'));
    final port = int.parse(url.substring(url.lastIndexOf(':') + 1));
    await _quiet();
    final server = await startLogged(
      net.serverSide(command, sdk.environment),
      file('server.log'),
      environment: sdk.environment,
      workingDirectory: sdk.package,
      nohup: true,
    );
    var listeners = const <int>[];
    for (var i = 0; i < 180 && listeners.isEmpty; i++) {
      listeners = await _listeners(port);
      if (listeners.isEmpty) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (listeners.isEmpty) stdout.writeln('port $port not up');
    final load = [
      if (which('timeout') != null) ...['timeout', '300'],
      _tungstenite('relic_baseline_ws_load'),
      '--url=$url/',
      '--connect=${net.host}',
      '--ca=${p.join(certs, 'ca_cert.pem')}',
      '--threads=${settings.ohaThreads}',
      '--pid=${listeners.firstOrNull ?? ''}',
    ];
    final napi = net.isVeth ? file('napi.txt') : null;
    void mark(String label, String when) {
      final now = DateTime.now().microsecondsSinceEpoch;
      napi?.writeAsStringSync(
        '$label $when ${net.napiTicks()} ${now ~/ 1000000}.'
        '${(now % 1000000).toString().padLeft(6, '0')}000\n',
        mode: FileMode.append,
      );
    }

    await _sample(file('threads.txt'));
    file('ws.jsonl').writeAsStringSync('');
    file('err').writeAsStringSync('');
    var exitCode = 0;
    for (final (label, arguments) in [
      (
        'text',
        [
          '--mode=echo',
          '--connections=${settings.wsConnections}',
          '--size=64',
          '--seconds=${settings.wsSeconds}',
          '--warmup=${settings.wsWarmup}',
        ],
      ),
      (
        'binary',
        [
          '--mode=echo',
          '--connections=${settings.wsConnections}',
          '--size=1024',
          '--binary',
          '--seconds=${settings.wsSeconds}',
          '--warmup=${settings.wsWarmup}',
        ],
      ),
      (
        'idle',
        [
          '--mode=idle',
          '--connections=${settings.wsIdle}',
          '--size=64',
          '--seconds=5',
        ],
      ),
    ]) {
      mark(label, 'before');
      exitCode = await runLogged(
        net.clientSide([...load, ...arguments], sdk.environment),
        stdoutFile: file('ws.jsonl'),
        stderrFile: file('err'),
        environment: sdk.environment,
        append: true,
      );
      mark(label, 'after');
    }
    await _unsample();
    _log('$name$suffix exit $exitCode');
    await _stop(server, port);
    await Future<void>.delayed(Duration(seconds: settings.pause));
  }
}
