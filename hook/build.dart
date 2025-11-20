import 'dart:io';

import 'package:native_assets_builder/native_assets_builder.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final packageName = config.packageName;
    final rustCrate = config.packageRoot.resolve('relic_hyper_server');
    output.addDependencies([
      rustCrate.resolve('Cargo.toml'),
      rustCrate.resolve('src/lib.rs'),
    ]);

    final cargoBuildResult = await Process.run('cargo', [
      'build',
      '--release',
    ], workingDirectory: rustCrate.toFilePath());

    if (cargoBuildResult.exitCode != 0) {
      throw Exception(
        'cargo build failed: ${cargoBuildResult.stdout}${cargoBuildResult.stderr}',
      );
    }

    final libName = 'relic_hyper_server';
    String dylibPath;
    String libAssetName;

    if (Platform.isWindows) {
      dylibPath = rustCrate.resolve('target/release/$libName.dll').toFilePath();
      libAssetName = '$libName.dll';
    } else if (Platform.isMacOS) {
      dylibPath =
          rustCrate.resolve('target/release/lib$libName.dylib').toFilePath();
      libAssetName = 'lib$libName.dylib';
    } else {
      // Assume linux
      dylibPath =
          rustCrate.resolve('target/release/lib$libName.so').toFilePath();
      libAssetName = 'lib$libName.so';
    }

    output.addAsset(
      Asset(
        name: libAssetName,
        path: dylibPath,
        target: config.target,
        packaging: Packaging.dynamic,
      ),
    );
  });
}
