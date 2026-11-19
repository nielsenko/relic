import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:cli_tools/cli_tools.dart';
import 'package:config/config.dart';
import 'package:git/git.dart';
import 'package:path/path.dart' as p;

/// The notes ref the benchmark results live under.
const _notesRef = 'benchmarks';

/// `notes store` and `notes extract`: benchmark results as git notes on
/// the tree they measured.
final class NotesCommand extends Command<void> {
  NotesCommand(StdOutLogger logger) {
    addSubcommand(_StoreCommand(logger));
    addSubcommand(_ExtractCommand(logger));
  }

  @override
  final name = 'notes';

  @override
  final description = 'Keep benchmark results as git notes';
}

enum _StoreOption<V> implements OptionDefinition<V> {
  file(
    FileOption(
      argPos: 0,
      helpText: 'The results to store, as bench_press run --save writes them',
      mode: PathExistMode.mustExist,
      mandatory: true,
    ),
  );

  const _StoreOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

final class _StoreCommand extends BetterCommand<_StoreOption<dynamic>, void> {
  final StdOutLogger _logger;

  _StoreCommand(this._logger) : super(options: _StoreOption.values);

  @override
  final name = 'store';

  @override
  final description =
      'Append a results file to the note on the tree of HEAD. The working '
      'tree must be clean, so the note names what was measured.';

  @override
  Future<void> runWithConfig(
    Configuration<_StoreOption<dynamic>> commandConfig,
  ) async {
    final file = commandConfig.value(_StoreOption.file);
    final git = await GitDir.fromExisting(p.current, allowSubdirectory: true);
    if (!await git.isWorkingTreeClean()) {
      throw StateError('Working copy not clean!');
    }
    final head = await git.commitFromRevision('HEAD');
    _logger.info('Appending benchmark results to: ${head.treeSha} (tree)');
    await git.runCommand([
      'notes',
      '--ref=$_notesRef',
      'append',
      '-F',
      file.path,
      head.treeSha,
    ], echoOutput: _logger.shouldLog(LogLevel.debug));
  }
}

enum _ExtractOption<V> implements OptionDefinition<V> {
  from(StringOption(argName: 'from', argAbbrev: 'f', defaultsTo: 'HEAD^')),
  to(StringOption(argName: 'to', argAbbrev: 't', defaultsTo: 'HEAD'));

  const _ExtractOption(this.option);

  @override
  final ConfigOptionBase<V> option;
}

final class _ExtractCommand
    extends BetterCommand<_ExtractOption<dynamic>, void> {
  final StdOutLogger _logger;

  _ExtractCommand(this._logger) : super(options: _ExtractOption.values);

  @override
  final name = 'extract';

  @override
  final description =
      'Print the stored results of the commits after --from up to --to';

  @override
  Future<void> runWithConfig(
    Configuration<_ExtractOption<dynamic>> commandConfig,
  ) async {
    final from = commandConfig.value(_ExtractOption.from);
    final to = commandConfig.value(_ExtractOption.to);

    final git = await GitDir.fromExisting(p.current, allowSubdirectory: true);
    final result = await git.runCommand([
      'log',
      '--format=%aI %H %T',
      '$from..$to',
    ]);

    final notes = StringBuffer();
    for (final line in (result.stdout as String).split('\n')) {
      final fields = line.split(' ');
      if (fields.length < 3) continue;
      final treeSha = fields[2];
      _logger.debug('${fields[1]} $treeSha ${fields[0]}');

      final note = await git.runCommand([
        'notes',
        '--ref=$_notesRef',
        'show',
        treeSha,
      ], throwOnError: false);
      if (note.exitCode == 0) notes.writeln(note.stdout);
    }
    _logger.info(notes.toString());
  }
}
