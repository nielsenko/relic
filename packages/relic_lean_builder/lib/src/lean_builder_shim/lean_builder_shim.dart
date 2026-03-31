// TODO(relic): Remove this shim once lean_builder supports analyzer ^12.0.0.
//
// lean_builder ^0.1.7 requires analyzer <11.0.0, but relic_generator requires
// analyzer ^12.0.0. Until lean_builder releases a compatible version, we
// provide minimal stub types so relic_lean_builder compiles and tests pass.
//
// When lean_builder is updated:
//   1. Add `lean_builder: ^X.Y.Z` back to pubspec.yaml
//   2. Replace `import 'lean_builder_shim/lean_builder_shim.dart'` with
//      `import 'package:lean_builder/builder.dart'`
//   3. Delete this file

import 'package:analyzer/dart/element/element.dart' as analyzer;

/// Stub for lean_builder's [BuildStep].
class BuildStep {
  const BuildStep();
}

/// Stub for lean_builder's [LeanElementAnnotation].
///
/// Named differently to avoid collision with analyzer's [ElementAnnotation].
class LeanElementAnnotation {
  const LeanElementAnnotation();
}

/// Stub for lean_builder's [LeanGenerator] annotation.
class LeanGenerator {
  final Set<String> outputExtensions;

  const LeanGenerator(this.outputExtensions);

  const LeanGenerator.shared() : outputExtensions = const <String>{};
}

/// Stub for lean_builder's [GeneratorForAnnotatedClass].
///
/// When lean_builder is available, this extends
/// `GeneratorForAnnotation<T>` which itself extends `Generator`.
/// The real class receives lean_builder's own element types, but since
/// relic_generator already works with analyzer elements, this shim uses
/// analyzer's [ClassElement] directly.
abstract class GeneratorForAnnotatedClass<T> {
  const GeneratorForAnnotatedClass();

  /// Override this to generate code for each annotated class.
  dynamic generateForClass(
    BuildStep buildStep,
    analyzer.ClassElement element,
    LeanElementAnnotation annotation,
  );
}
