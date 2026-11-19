import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The directory of this package, which holds bin/, baselines/, report/
/// and load.md.
///
/// A program started with `dart run` finds it through its package
/// configuration. A `dart build cli` bundle has none and takes it from
/// `BENCH_PACKAGE`, or from the current directory.
Directory packageRoot() {
  final configured = Platform.environment['BENCH_PACKAGE'];
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:benchmark/'));
  if (lib != null && lib.isScheme('file')) {
    return Directory(p.dirname(p.normalize(lib.toFilePath())));
  }
  return Directory.current;
}
