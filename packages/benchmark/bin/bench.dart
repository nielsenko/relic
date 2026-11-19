// The benchmark tools of this package, one command each.
//
//   dart run bin/bench.dart --help
//
// The micro benchmarks are in benchmark/ and run through bench_press:
//
//   dart run bench_press run benchmark/
//   dart run bench_press run -t aot benchmark/
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:benchmark/src/commands/notes.dart';
import 'package:cli_tools/cli_tools.dart';

final _logger = StdOutLogger(LogLevel.info);

void _setLogLevel({
  required CommandRunnerLogLevel parsedLogLevel,
  String? commandName,
}) {
  _logger.logLevel = switch (parsedLogLevel) {
    CommandRunnerLogLevel.quiet => LogLevel.error,
    CommandRunnerLogLevel.verbose => LogLevel.debug,
    CommandRunnerLogLevel.normal => LogLevel.info,
  };
}

Future<void> main(List<String> args) async {
  // ignore: inference_failure_on_instance_creation
  final runner = BetterCommandRunner(
    'bench',
    'Relic benchmark tools',
    setLogLevel: _setLogLevel,
  )..addCommand(NotesCommand(_logger));
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln('${e.message}\n\n${e.usage}');
    exitCode = 64;
  }
}
