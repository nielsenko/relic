import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

import '../sweep/paths.dart';

/// `gcp create`, `gcp fetch` and `gcp delete`: a GCP instance that runs
/// the sweep once, and its results.
final class GcpCommand extends Command<void> {
  GcpCommand() {
    addSubcommand(_CreateCommand());
    addSubcommand(_FetchCommand());
    addSubcommand(_DeleteCommand());
  }

  @override
  final name = 'gcp';

  @override
  final description = 'Run the sweep on a GCP instance and fetch its results';
}

/// Runs `gcloud` with [arguments] on this terminal, or prints the command
/// with [dryRun]. Returns its exit code.
Future<int> _gcloud(List<String> arguments, {bool dryRun = false}) async {
  if (dryRun) {
    stdout.writeln(['gcloud', ...arguments].join('\n'));
    return 0;
  }
  final process = await Process.start(
    'gcloud',
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

/// The machine series that expose a PMU to a VM.
const _pmuSeries = ['c4-', 'c4a-', 'm4-'];

const _project = StringOption(
  argName: 'project',
  envName: 'PROJECT',
  helpText: 'The GCP project',
  defaultsTo: 'relic-bench',
);

const _dryRun = FlagOption(
  argName: 'dry-run',
  helpText: 'Print the gcloud command, an argument a line, and do not run it',
  defaultsTo: false,
  negatable: false,
);

enum GcpCreateOption<V> implements OptionDefinition<V> {
  name(
    StringOption(
      argPos: 0,
      helpText: 'The name of the instance',
      defaultsTo: 'relic-bench',
    ),
  ),
  type(
    StringOption(
      argPos: 1,
      helpText:
          'The machine type. A VM gets one thread per core. A -metal type '
          'does not, since the platform has no such flag for bare metal, '
          'and the OS turns SMT off there. C4A has one thread per core '
          'already. An arm type (c4a-) gets the arm64 image. The type '
          'needs a PMU unless --pmu is none, see there',
      defaultsTo: 'c4-standard-48',
    ),
  ),
  zone(
    StringOption(argPos: 2, helpText: 'The zone', defaultsTo: 'europe-west1-b'),
  ),
  project(_project),
  maxRun(
    StringOption(
      argName: 'max-run',
      envName: 'MAX_RUN',
      helpText: 'A VM stops after this long',
      defaultsTo: '8h',
    ),
  ),
  spot(
    IntOption(
      argName: 'spot',
      envName: 'SPOT',
      helpText:
          '1 asks for spot pricing. A preemption then loses the whole run, '
          'since the results are uploaded at its end',
      defaultsTo: 0,
      min: 0,
      max: 1,
    ),
  ),
  diskGb(
    IntOption(
      argName: 'disk-gb',
      envName: 'DISK_GB',
      helpText: 'The size of the boot disk',
      defaultsTo: 50,
      min: 10,
    ),
  ),
  pmu(
    StringOption(
      argName: 'pmu',
      envName: 'PMU',
      helpText:
          'architectural, standard or enhanced exposes hardware counters '
          'to the VM, on the series that offer them: C4, C4A and M4. '
          'architectural holds the instructions and cycles the sweep '
          'reads. none creates a VM without counters, on any type. Bare '
          'metal has its PMU without the flag',
      defaultsTo: 'architectural',
      allowedValues: ['none', 'architectural', 'standard', 'enhanced'],
    ),
  ),
  branch(
    StringOption(
      argName: 'relic-branch',
      envName: 'RELIC_BRANCH',
      helpText: 'The branch the instance sweeps',
      defaultsTo: 'chore-benchmark-sweep',
    ),
  ),
  sweepEnv(
    StringOption(
      argName: 'sweep-env',
      envName: 'SWEEP_ENV',
      helpText: 'The environment of the sweep on the instance',
      defaultsTo: 'QUIET=0 PAUSE=5 OHA_THREADS=8 NET=veth',
    ),
  ),
  sweepOnly(
    StringOption(
      argName: 'sweep-only',
      envName: 'SWEEP_ONLY',
      helpText: 'The targets to run, separated by spaces. All by default',
    ),
  ),
  sweepScript(
    StringOption(
      argName: 'sweep-script',
      envName: 'SWEEP_SCRIPT',
      helpText: 'The bench command the instance runs: sweep or kernel',
    ),
  ),
  dartSdks(
    StringOption(
      argName: 'dart-sdks',
      envName: 'DART_SDKS',
      helpText:
          'The Dart SDK versions the instance installs, separated by '
          'spaces. With more than one, every Dart target runs on each',
    ),
  ),
  keep(
    IntOption(
      argName: 'keep',
      envName: 'KEEP',
      helpText: '1 leaves the instance running after the sweep',
      defaultsTo: 0,
      min: 0,
      max: 1,
    ),
  ),
  patch(
    StringOption(
      argName: 'relic-patch',
      envName: 'RELIC_PATCH',
      helpText: 'A patch file the instance applies to its clone',
    ),
  ),
  dryRun(_dryRun);

  const GcpCreateOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `gcp create [name] [machine-type] [zone]`.
final class _CreateCommand
    extends BetterCommand<GcpCreateOption<dynamic>, void> {
  _CreateCommand() : super(options: GcpCreateOption.values);

  @override
  final name = 'create';

  @override
  final description =
      'Create a GCP instance that runs the sweep once, uploads its results '
      'and shuts down, by tool/sweep/gcp/startup.sh';

  @override
  Future<void> runWithConfig(
    Configuration<GcpCreateOption<dynamic>> commandConfig,
  ) async {
    T value<T>(GcpCreateOption<T> option) => commandConfig.value(option);
    T? optional<T>(GcpCreateOption<T> option) =>
        commandConfig.optionalValue(option);
    final name = value(GcpCreateOption.name);
    final type = value(GcpCreateOption.type);
    final zone = value(GcpCreateOption.zone);
    final project = value(GcpCreateOption.project);
    final metal = type.endsWith('-metal');
    final arm = type.startsWith('c4a-');
    final pmu = value(GcpCreateOption.pmu);
    if (pmu != 'none' && !metal && !_pmuSeries.any(type.startsWith)) {
      stderr.writeln(
        '$type has no PMU, so the sweep would read no counters. Pick a '
        '${_pmuSeries.join(', ')} type, or pass --pmu=none',
      );
      exitCode = 64;
      return;
    }
    final metadata = [
      'relic-branch=${value(GcpCreateOption.branch)}',
      'sweep-env=${value(GcpCreateOption.sweepEnv)}',
      'keep=${value(GcpCreateOption.keep)}',
      'require-pmu=${pmu != 'none' && !metal ? 1 : 0}',
      if (optional(GcpCreateOption.sweepOnly) case final only?
          when only.isNotEmpty)
        'sweep-only=$only',
      if (optional(GcpCreateOption.sweepScript) case final script?
          when script.isNotEmpty)
        'sweep-script=$script',
      if (optional(GcpCreateOption.dartSdks) case final sdks?
          when sdks.isNotEmpty)
        'dart-sdks=$sdks',
    ];
    final startup = p.join(
      packageRoot().path,
      'tool',
      'sweep',
      'gcp',
      'startup.sh',
    );
    final files = [
      'startup-script=$startup',
      if (optional(GcpCreateOption.patch) case final patch?
          when patch.isNotEmpty)
        'relic-patch=$patch',
    ];
    final dryRun = value(GcpCreateOption.dryRun);
    exitCode = await _gcloud([
      'compute',
      'instances',
      'create',
      name,
      '--project=$project',
      '--zone=$zone',
      '--machine-type=$type',
      '--image-family=ubuntu-2404-lts-${arm ? 'arm64' : 'amd64'}',
      '--image-project=ubuntu-os-cloud',
      '--boot-disk-type=hyperdisk-balanced',
      '--boot-disk-size=${value(GcpCreateOption.diskGb)}GB',
      '--service-account=relic-bench-runner@$project.iam.gserviceaccount.com',
      '--scopes=storage-rw',
      '--metadata=${metadata.join(',')}',
      '--metadata-from-file=${files.join(',')}',
      if (!metal) ...[
        if (!arm) '--threads-per-core=1',
        '--instance-termination-action=STOP',
        '--max-run-duration=${value(GcpCreateOption.maxRun)}',
      ],
      if (value(GcpCreateOption.spot) == 1 && !metal)
        '--provisioning-model=SPOT',
      if (pmu != 'none' && !metal) '--performance-monitoring-unit=$pmu',
    ], dryRun: dryRun);
    if (dryRun || exitCode != 0) return;
    stdout
      ..writeln(
        'follow with: gcloud compute instances tail-serial-port-output '
        '$name --zone=$zone --project=$project',
      )
      ..writeln('delete it when it has stopped: bench gcp delete $name $zone');
  }
}

enum GcpFetchOption<V> implements OptionDefinition<V> {
  run(
    StringOption(
      argPos: 0,
      helpText: 'The run to copy down. Without one, the runs are listed',
    ),
  ),
  destination(
    StringOption(
      argPos: 1,
      helpText: 'Where the run goes, sweep-out/<run> by default',
    ),
  ),
  bucket(
    StringOption(
      argName: 'bucket',
      envName: 'BUCKET',
      helpText: 'The bucket of the results',
      defaultsTo: 'relic-bench-nights',
    ),
  ),
  dryRun(_dryRun);

  const GcpFetchOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `gcp fetch [<run> [<destination>]]`.
final class _FetchCommand extends BetterCommand<GcpFetchOption<dynamic>, void> {
  _FetchCommand() : super(options: GcpFetchOption.values);

  @override
  final name = 'fetch';

  @override
  final description = 'List the sweeps in the bucket, or copy one down';

  @override
  Future<void> runWithConfig(
    Configuration<GcpFetchOption<dynamic>> commandConfig,
  ) async {
    final bucket = commandConfig.value(GcpFetchOption.bucket);
    final dryRun = commandConfig.value(GcpFetchOption.dryRun);
    final run = commandConfig.optionalValue(GcpFetchOption.run);
    if (run == null) {
      exitCode = await _gcloud([
        'storage',
        'ls',
        'gs://$bucket/',
      ], dryRun: dryRun);
      return;
    }
    final destination =
        commandConfig.optionalValue(GcpFetchOption.destination) ??
        p.join('sweep-out', run);
    if (!dryRun) Directory(destination).createSync(recursive: true);
    exitCode = await _gcloud([
      'storage',
      'cp',
      '-r',
      'gs://$bucket/$run/*',
      '$destination/',
    ], dryRun: dryRun);
    if (exitCode == 0) stdout.writeln(destination);
  }
}

enum GcpDeleteOption<V> implements OptionDefinition<V> {
  name(
    StringOption(
      argPos: 0,
      helpText: 'The name of the instance',
      defaultsTo: 'relic-bench',
    ),
  ),
  zone(
    StringOption(argPos: 1, helpText: 'The zone', defaultsTo: 'europe-west4-a'),
  ),
  project(_project),
  dryRun(_dryRun);

  const GcpDeleteOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

/// `gcp delete [name] [zone]`.
final class _DeleteCommand
    extends BetterCommand<GcpDeleteOption<dynamic>, void> {
  _DeleteCommand() : super(options: GcpDeleteOption.values);

  @override
  final name = 'delete';

  @override
  final description =
      'Delete a stopped sweep instance and its boot disk. A shut down '
      'instance stays in the project and its disk stays billed until this '
      'runs. An instance that has not stopped is left alone.';

  @override
  Future<void> runWithConfig(
    Configuration<GcpDeleteOption<dynamic>> commandConfig,
  ) async {
    final name = commandConfig.value(GcpDeleteOption.name);
    final zone = commandConfig.value(GcpDeleteOption.zone);
    final project = commandConfig.value(GcpDeleteOption.project);
    final dryRun = commandConfig.value(GcpDeleteOption.dryRun);
    final describe = [
      'compute',
      'instances',
      'describe',
      name,
      '--project=$project',
      '--zone=$zone',
      '--format=value(status)',
    ];
    if (dryRun) {
      await _gcloud(describe, dryRun: true);
    } else {
      final status = await Process.run('gcloud', describe);
      final state = (status.stdout as String).trim();
      if (status.exitCode != 0 || state != 'TERMINATED') {
        stderr
          ..write(status.stderr)
          ..writeln('$name is $state, not deleting it');
        exitCode = 1;
        return;
      }
    }
    exitCode = await _gcloud([
      'compute',
      'instances',
      'delete',
      name,
      '--project=$project',
      '--zone=$zone',
      '--quiet',
    ], dryRun: dryRun);
  }
}
