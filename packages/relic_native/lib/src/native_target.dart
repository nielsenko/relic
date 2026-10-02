import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// A target the package ships a prebuilt library for. Shared by
/// `hook/build.dart`, which picks the library for the target being built,
/// and `tool/build_binaries.dart`, which builds all of them before
/// publishing.
final class NativeTarget {
  const NativeTarget._(this.os, this.architecture, this.zigTriple);

  /// The operating system this target builds for.
  final OS os;

  /// The CPU architecture this target builds for.
  final Architecture architecture;

  /// The `-Dtarget` passed to `zig build`. Apple triples carry the minimum
  /// OS version.
  final String zigTriple;

  /// Every target with a prebuilt library. On any other target the hook
  /// emits no asset.
  static const all = [
    NativeTarget._(OS.macOS, Architecture.arm64, 'aarch64-macos.11.0'),
    NativeTarget._(OS.macOS, Architecture.x64, 'x86_64-macos.10.15'),
    NativeTarget._(OS.linux, Architecture.x64, 'x86_64-linux-gnu'),
    NativeTarget._(OS.linux, Architecture.arm64, 'aarch64-linux-gnu'),
    NativeTarget._(OS.windows, Architecture.x64, 'x86_64-windows-gnu'),
    NativeTarget._(OS.windows, Architecture.arm64, 'aarch64-windows-gnu'),
  ];

  /// The target matching [code], or null when none is supported.
  static NativeTarget? of(final CodeConfig code) {
    for (final target in all) {
      if (target.os == code.targetOS &&
          target.architecture == code.targetArchitecture) {
        return target;
      }
    }
    return null;
  }

  /// Directory under `binary/` holding this target's prebuilt library.
  String get directory => '${os.name}-${architecture.name}';

  /// The file name of the library on this target's operating system.
  String get libraryName => switch (os) {
    OS.macOS => 'librelic_native.dylib',
    OS.windows => 'relic_native.dll',
    _ => 'librelic_native.so',
  };

  /// zig installs DLLs to `bin/`, and other shared libraries to `lib/`.
  String get _installSubdirectory => os == OS.windows ? 'bin' : 'lib';

  /// Builds the library for this target from source and returns it.
  Future<File> build({
    required final Uri packageRoot,
    required final Uri outputDirectory,
    final Uri? cacheDirectory,
  }) async {
    final prefix = outputDirectory.resolve('zig-out/$directory/');
    await zigBuild(
      packageRoot: packageRoot,
      zigTriple: zigTriple,
      prefix: prefix,
      cacheRoot: cacheDirectory,
    );
    final built = File.fromUri(
      prefix.resolve('$_installSubdirectory/$libraryName'),
    );
    if (!built.existsSync()) {
      throw StateError('zig build succeeded but ${built.path} is missing.');
    }
    return built;
  }
}

/// Runs `zig build` for [zigTriple], installing into [prefix].
///
/// [cacheRoot] (if set) holds zig's local cache. The global cache stays
/// where zig keeps it: `zig build` takes no flag for it as of 0.17, and
/// anyzig keeps its compilers there. It moves under [cacheRoot] only on
/// Windows without `LOCALAPPDATA`, which is how Dart 3.10.0 runs a hook
/// and where zig finds no place for it.
Future<void> zigBuild({
  required final Uri packageRoot,
  required final String zigTriple,
  required final Uri prefix,
  final Uri? cacheRoot,
}) async {
  final zig = await _zigExecutable(packageRoot);
  final args = [
    'build',
    '-Dtarget=$zigTriple',
    '--release=fast',
    '-Dstrip=true',
    '-p',
    prefix.toFilePath(),
    if (cacheRoot != null) ...[
      '--cache-dir',
      cacheRoot.resolve('local/').toFilePath(),
    ],
  ];
  final environment = Platform.environment;
  final result = await Process.run(
    zig,
    args,
    workingDirectory: packageRoot.toFilePath(),
    environment: {
      if (Platform.isWindows &&
          cacheRoot != null &&
          !environment.containsKey('LOCALAPPDATA') &&
          !environment.containsKey('ZIG_GLOBAL_CACHE_DIR'))
        'ZIG_GLOBAL_CACHE_DIR': cacheRoot.resolve('global/').toFilePath(),
    },
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      zig,
      args,
      'zig build failed with exit code ${result.exitCode}:\n'
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

/// Resolves a zig matching `minimum_zig_version` in build.zig.zon. The `zig`
/// on PATH may be that version or anyzig
/// (https://github.com/marler8997/anyzig), which reads the same field when
/// run in the package root.
Future<String> _zigExecutable(final Uri packageRoot) async {
  final zon = await File.fromUri(
    packageRoot.resolve('build.zig.zon'),
  ).readAsString();
  final pinned = RegExp(
    r'\.minimum_zig_version = "([^"]+)"',
  ).firstMatch(zon)![1]!;

  String? found;
  try {
    final result = await Process.run('zig', [
      'version',
    ], workingDirectory: packageRoot.toFilePath());
    if (result.exitCode == 0) found = (result.stdout as String).trim();
  } on ProcessException {
    // No zig on PATH.
  }
  if (found == pinned) return 'zig';

  throw StateError(
    'Building relic_native from source needs zig $pinned '
    '(${found == null ? 'no zig on PATH' : 'found zig $found'}). Install '
    'zig $pinned, or anyzig (https://github.com/marler8997/anyzig), which '
    'selects the version from build.zig.zon.',
  );
}
