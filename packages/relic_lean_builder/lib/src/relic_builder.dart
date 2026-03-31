import 'package:analyzer/dart/element/element.dart';
import 'package:relic_annotations/relic_annotations.dart';
import 'package:relic_generator/relic_generator.dart';

// TODO(relic): Replace with `import 'package:lean_builder/builder.dart'`
// once lean_builder supports analyzer ^12.0.0.
import 'lean_builder_shim/lean_builder_shim.dart';

/// Relic code generator that produces `_$FooApi` classes implementing
/// `RouterInjectable` from `@Api` annotated classes.
///
/// Generates `.relic.g.dart` part files that contain the abstract base class
/// with routing setup code.
@LeanGenerator({'.relic.g.dart'})
class RelicGenerator extends GeneratorForAnnotatedClass<Api> {
  @override
  dynamic generateForClass(
    BuildStep buildStep,
    ClassElement element,
    LeanElementAnnotation annotation,
  ) {
    final library = element.library;
    final models = analyzeLibrary(library);

    final className = element.name;
    if (className == null) {
      throw StateError('Class element has no name');
    }

    final model = models.firstWhere(
      (m) => m.className == className,
      orElse: () => throw StateError('No @Api model found for $className'),
    );

    final diagnostics = analyzeDiagnostics(library);
    for (final diagnostic in diagnostics) {
      if (diagnostic.severity == DiagnosticSeverity.error) {
        throw StateError('Generator error: ${diagnostic.message}');
      }
    }

    final sourceFileName = element.library.uri.pathSegments.last;
    return emitHandlerCode(model, sourceFileName: sourceFileName);
  }
}
