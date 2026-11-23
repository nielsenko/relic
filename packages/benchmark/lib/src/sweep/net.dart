import 'dart:convert';
import 'dart:io';

import '../cpu.dart';
import 'processes.dart';

/// The network between the servers and the load tools of a sweep.
///
/// `lo` puts both on the loopback. With `veth` every server runs in network
/// namespace srv and every load tool in cli, and a veth pair joins the
/// two. Its ends have GRO on and TSO off, so TCP takes NAPI's receive
/// path, as packets from a NIC do. Each end's NAPI runs in [queues]
/// threads, a CPU each at the top of the CPU list. The servers run on the
/// lower half of the other CPUs, [serverCpus], and the load tools on the
/// upper half, [clientCpus], so neither takes the other's CPUs.
///
/// veth takes Linux, root through `sudo -n`, ip, ethtool, ping, taskset,
/// setpriv, prlimit and the veth module.
final class Net {
  /// `lo` or `veth`.
  final String kind;

  /// The address the servers listen on and the load tools connect to.
  final String host;

  /// The server's end of the veth pair, or null on the loopback.
  final String? napiDevice;

  /// NAPI threads at each end of the pair.
  final int queues;

  /// The CPU count of the machine.
  final int cpus;

  /// What runs a command as root: empty for root itself.
  final List<String> _sudo;

  /// The setpriv options that take a command back to this user.
  final List<String> _me;

  Net._(
    this.kind,
    this.host,
    this.napiDevice,
    this.queues,
    this.cpus,
    this._sudo,
    this._me,
  );

  bool get isVeth => kind == 'veth';

  /// The CPUs the servers and the load tools split between them.
  int get _workCpus => cpus - 2 * queues;

  /// How many CPUs the servers get over veth.
  int get serverCpuCount => _workCpus ~/ 2;

  /// The CPUs of the servers, as taskset writes a list.
  String get serverCpus => '0-${serverCpuCount - 1}';

  /// The CPUs of the load tools, http_load, zrk, the WebSocket client and
  /// the thread sampler, as taskset writes a list.
  String get clientCpus => '${_workCpus ~/ 2}-${_workCpus - 1}';

  /// The network [kind] names, `lo` or `veth`. [queues] is the NAPI
  /// thread count of each veth end, the CPU count over 8 from 24 CPUs up
  /// and 2 below when null.
  static Future<Net> create(String kind, {int? queues}) async {
    switch (kind) {
      case 'lo':
        return Net._('lo', '127.0.0.1', null, 0, 0, const [], const []);
      case 'veth':
        final cpus = int.parse(await outputOf(['nproc']));
        final root = await outputOf(['id', '-u']) == '0';
        return Net._(
          'veth',
          '10.77.0.1',
          'vsrv',
          queues ?? (cpus >= 24 ? cpus ~/ 8 : 2),
          cpus,
          root ? const [] : const ['sudo', '-n', '-E'],
          [
            '--reuid=${await outputOf(['id', '-u'])}',
            '--regid=${await outputOf(['id', '-g'])}',
            '--init-groups',
          ],
        );
      default:
        throw FormatException('NET is lo or veth, not $kind');
    }
  }

  /// [command] as root in [namespace].
  List<String> inNamespace(String namespace, List<String> command) => [
    ..._sudo,
    'ip',
    'netns',
    'exec',
    namespace,
    ...command,
  ];

  /// [command] as root.
  List<String> _asRoot(List<String> command) => [..._sudo, ...command];

  /// [command] as this user in [namespace], with this process's open-file
  /// limits, which sudo's pam_limits resets, on [cpuList].
  List<String> _asMeIn(
    String namespace,
    String cpuList,
    List<String> command,
    Map<String, String> environment, {
    Map<String, String> extra = const {},
  }) {
    final (soft, hard) = openFileLimits();
    return inNamespace(namespace, [
      'prlimit',
      '--nofile=$soft:$hard',
      'setpriv',
      ..._me,
      'env',
      'HOME=${environment['HOME'] ?? ''}',
      'PATH=${environment['PATH'] ?? ''}',
      for (final MapEntry(:key, :value) in extra.entries) '$key=$value',
      'taskset',
      '-c',
      cpuList,
      ...command,
    ]);
  }

  /// [command] where the servers run, with BENCH_ADDRESS set to [host]
  /// over veth. [environment] is the environment the command starts in.
  /// [onServerCpus] false keeps it in the servers' namespace but on the
  /// load tools' CPUs, for http_load, which meters the server from there.
  List<String> serverSide(
    List<String> command,
    Map<String, String> environment, {
    bool onServerCpus = true,
  }) => isVeth
      ? _asMeIn(
          'srv',
          onServerCpus ? serverCpus : clientCpus,
          command,
          environment,
          extra: {
            'BENCH_ADDRESS': host,
            'BENCH_ZRK': ?environment['BENCH_ZRK'],
            'RELIC_BENCH_PG_HOST': ?environment['RELIC_BENCH_PG_HOST'],
          },
        )
      : command;

  /// [command] where the load tools run.
  List<String> clientSide(
    List<String> command,
    Map<String, String> environment,
  ) => isVeth ? _asMeIn('cli', clientCpus, command, environment) : command;

  /// The address the servers reach the postgres of the async pass at,
  /// which runs where the load tools do.
  String get databaseHost => isVeth ? '10.77.0.2' : '127.0.0.1';

  /// [command] as root where the load tools run, on their CPUs over veth.
  List<String> clientSideAsRoot(List<String> command) => isVeth
      ? inNamespace('cli', ['taskset', '-c', clientCpus, ...command])
      : ['sudo', '-n', ...command];

  /// What runs zrk on the client side, for `BENCH_ZRK`, or null on the
  /// loopback, where http_load finds zrk on its PATH.
  String? zrkCommand(Map<String, String> environment) {
    if (!isVeth) return null;
    final zrk = which('zrk', environment: environment);
    if (zrk == null) return null;
    return jsonEncode(clientSide([zrk], environment));
  }

  /// The packets the NAPI of a veth end has taken, the server's end by
  /// default.
  Future<int> packets({
    String namespace = 'srv',
    String device = 'vsrv',
  }) async {
    final statistics = await outputOf(
      inNamespace(namespace, ['ethtool', '-S', device]),
    );
    var packets = 0;
    final queue = RegExp(r'rx_queue_\d+_xdp_packets:\s*(\d+)');
    for (final match in queue.allMatches(statistics)) {
      packets += int.parse(match.group(1)!);
    }
    return packets;
  }

  /// The clock ticks the NAPI threads of the server's end have used, 0 on
  /// the loopback.
  int napiTicks() {
    final device = napiDevice;
    if (device == null) return 0;
    var ticks = 0;
    for (final pid in napiThreads(device)) {
      final used = ticksOf('/proc/$pid/stat');
      if (used != null) ticks += used.$1 + used.$2;
    }
    return ticks;
  }

  /// Removes the namespaces and the pair with them.
  Future<void> teardown() async {
    if (!isVeth) return;
    await succeeds(_asRoot(['ip', 'netns', 'del', 'srv']));
    await succeeds(_asRoot(['ip', 'netns', 'del', 'cli']));
  }

  /// Makes the pair, checks it and writes how it is set up to [log], with
  /// what failed. Returns whether the pair is usable.
  Future<bool> setup(File log) async {
    if (!isVeth) return true;
    final notes = <String>[];
    final ok = await _make(notes) && await _check(notes);
    log.writeAsStringSync(notes.map((n) => '$n\n').join());
    if (!ok) {
      final failures = notes.where((n) => !n.startsWith(' ')).toList();
      stderr.writeln(
        failures.skip(failures.length > 4 ? failures.length - 4 : 0).join('\n'),
      );
    }
    return ok;
  }

  Future<bool> _root(List<String> command, List<String> notes) async {
    final result = await Process.run(
      _asRoot(command).first,
      _asRoot(command).sublist(1),
    );
    if (result.exitCode == 0) return true;
    notes.add('${command.join(' ')}: ${(result.stderr as String).trim()}');
    return false;
  }

  Future<bool> _make(List<String> notes) async {
    final q = '$queues';
    await teardown();
    await succeeds(_asRoot(['modprobe', 'veth']));
    if (!await _root(['ip', 'netns', 'add', 'srv'], notes)) return false;
    if (!await _root(['ip', 'netns', 'add', 'cli'], notes)) return false;
    if (!await _root([
      'ip', 'link', 'add', 'vsrv', 'numtxqueues', q, 'numrxqueues', q, //
      'type',
      'veth',
      'peer',
      'name',
      'vcli',
      'numtxqueues',
      q,
      'numrxqueues',
      q,
    ], notes)) {
      return false;
    }
    await _root(['ip', 'link', 'set', 'vsrv', 'netns', 'srv'], notes);
    await _root(['ip', 'link', 'set', 'vcli', 'netns', 'cli'], notes);
    await _root([
      'ip',
      '-n',
      'srv',
      'addr',
      'add',
      '$host/24',
      'dev',
      'vsrv',
    ], notes);
    await _root([
      'ip',
      '-n',
      'cli',
      'addr',
      'add',
      '10.77.0.2/24',
      'dev',
      'vcli',
    ], notes);
    for (final (namespace, device, first) in [
      ('srv', 'vsrv', cpus - 2 * queues),
      ('cli', 'vcli', cpus - queues),
    ]) {
      await _root(['ip', '-n', namespace, 'link', 'set', 'lo', 'up'], notes);
      await _root(['ip', '-n', namespace, 'link', 'set', device, 'up'], notes);
      await _root([
        'ip', 'netns', 'exec', namespace, //
        'ethtool', '-K', device, 'tso', 'off', 'gro', 'on',
      ], notes);
      await _root([
        'ip', 'netns', 'exec', namespace, //
        'sh', '-c', 'echo 1 > /sys/class/net/$device/threaded',
      ], notes);
      for (final (i, pid) in napiThreads(device).indexed) {
        await succeeds(
          _asRoot(['taskset', '-pc', '${first + i % queues}', '$pid']),
        );
      }
    }
    notes.add(
      'net: veth, $queues queues an end, servers on CPUs $serverCpus, load '
      'tools on $clientCpus, NAPI on ${cpus - 2 * queues}-${cpus - queues - 1} for '
      'vsrv and ${cpus - queues}-${cpus - 1} for vcli',
    );
    for (final (namespace, device) in const [
      ('srv', 'vsrv'),
      ('cli', 'vcli'),
    ]) {
      for (final pid in napiThreads(device)) {
        final affinity = await outputOf(_asRoot(['taskset', '-pc', '$pid']));
        notes.add(
          '$device NAPI thread $pid on '
          '${affinity.substring(affinity.lastIndexOf(': ') + 2)}',
        );
      }
      final features = await outputOf(
        inNamespace(namespace, ['ethtool', '-k', device]),
      );
      notes.addAll(
        const LineSplitter()
            .convert(features)
            .where(
              (line) =>
                  line.startsWith('tcp-segmentation-offload') ||
                  line.startsWith('generic-receive-offload'),
            ),
      );
      notes.addAll(
        const LineSplitter().convert(
          await outputOf(
            inNamespace(namespace, ['ip', '-d', 'link', 'show', device]),
            mergeStderr: true,
          ),
        ),
      );
    }
    return true;
  }

  /// Whether each end has threaded NAPI with [queues] threads, GRO on and
  /// TSO off, and pings between the ends go through both ends' NAPI.
  Future<bool> _check(List<String> notes) async {
    var ok = true;
    for (final (namespace, device) in const [
      ('srv', 'vsrv'),
      ('cli', 'vcli'),
    ]) {
      final threads = napiThreads(device).length;
      final threaded = await outputOf(
        inNamespace(namespace, ['cat', '/sys/class/net/$device/threaded']),
      );
      if (threaded != '1' || threads != queues) {
        notes.add('$device: $threads NAPI threads, not $queues');
        ok = false;
      }
      final features = const LineSplitter().convert(
        await outputOf(inNamespace(namespace, ['ethtool', '-k', device])),
      );
      if (!features.any((l) => l.startsWith('tcp-segmentation-offload: off')) ||
          !features.any((l) => l.startsWith('generic-receive-offload: on'))) {
        notes.add('$device: TSO is on or GRO off');
        ok = false;
      }
    }
    final before = [
      await packets(),
      await packets(namespace: 'cli', device: 'vcli'),
    ];
    if (!await succeeds(
      inNamespace('cli', ['ping', '-q', '-c', '20', '-i', '0.05', host]),
    )) {
      notes.add('no ping from cli to $host');
      return false;
    }
    final after = [
      await packets(),
      await packets(namespace: 'cli', device: 'vcli'),
    ];
    if (after[0] - before[0] < 20 || after[1] - before[1] < 20) {
      notes.add(
        'pings bypassed NAPI: ${after[0] - before[0]} and '
        '${after[1] - before[1]} packets',
      );
      ok = false;
    }
    return ok;
  }
}
