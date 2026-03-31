import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../analyzer/annotation_reader.dart';
import 'diagnostic.dart';

/// Analyzes a library for diagnostic issues in @Api annotated classes.
List<GeneratorDiagnostic> analyzeDiagnostics(LibraryElement library) {
  final diagnostics = <GeneratorDiagnostic>[];

  for (final classElement in library.classes) {
    if (!hasAnnotation(classElement, 'Api')) continue;
    _analyzeApiClass(classElement, diagnostics);
  }

  return diagnostics;
}

void _analyzeApiClass(
  ClassElement classElement,
  List<GeneratorDiagnostic> diagnostics,
) {
  final className = classElement.name ?? '';

  for (final method in classElement.methods) {
    if (method.isStatic || method.isPrivate) continue;
    _analyzeMethod(method, className, diagnostics);
  }

  // Validate class-level @Use annotations.
  for (final metadata in classElement.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == 'Use') {
      _validateUseAnnotation(
        metadata.computeConstantValue(),
        className,
        diagnostics,
      );
    }
  }
}

void _analyzeMethod(
  MethodElement method,
  String className,
  List<GeneratorDiagnostic> diagnostics,
) {
  final hasHttp = [
    'Get',
    'Post',
    'Put',
    'Delete',
    'Patch',
  ].any((name) => hasAnnotation(method, name));
  if (!hasHttp) return;

  final methodName = method.name ?? '';

  // Check for multiple HTTP annotations.
  final httpAnnotationCount = [
    'Get',
    'Post',
    'Put',
    'Delete',
    'Patch',
  ].where((name) => hasAnnotation(method, name)).length;
  if (httpAnnotationCount > 1) {
    diagnostics.add(
      GeneratorDiagnostic(
        severity: DiagnosticSeverity.error,
        message:
            'Method "$methodName" has multiple HTTP method annotations. '
            'Only one is allowed.',
        elementName: '$className.$methodName',
      ),
    );
  }

  _validateParameters(method, className, methodName, diagnostics);
  _validateReturnType(method, className, methodName, diagnostics);

  // Validate method-level @Use annotations.
  for (final metadata in method.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == 'Use') {
      _validateUseAnnotation(
        metadata.computeConstantValue(),
        '$className.$methodName',
        diagnostics,
      );
    }
  }
}

void _validateParameters(
  MethodElement method,
  String className,
  String methodName,
  List<GeneratorDiagnostic> diagnostics,
) {
  int bodyParamCount = 0;

  for (final param in method.formalParameters) {
    if (hasAnnotation(param, 'JsonBody') || hasAnnotation(param, 'FormBody')) {
      bodyParamCount++;
    }

    // Check that @Req is typed as Request.
    if (hasAnnotation(param, 'Req')) {
      final paramType = param.type;
      if (paramType is InterfaceType && paramType.element.name != 'Request') {
        diagnostics.add(
          GeneratorDiagnostic(
            severity: DiagnosticSeverity.error,
            message: '@Req parameter "${param.name}" must be typed as Request.',
            elementName: '$className.$methodName',
            suggestion: 'Change the type to Request.',
          ),
        );
      }
    }

    // Check for multiple source annotations on one param.
    final sourceAnnotations = [
      'Path',
      'Query',
      'Header',
      'JsonBody',
      'FormBody',
      'Req',
    ].where((name) => hasAnnotation(param, name)).toList();
    if (sourceAnnotations.length > 1) {
      diagnostics.add(
        GeneratorDiagnostic(
          severity: DiagnosticSeverity.error,
          message:
              'Parameter "${param.name}" has multiple source annotations: '
              '${sourceAnnotations.join(', ')}. Only one is allowed.',
          elementName: '$className.$methodName',
        ),
      );
    }
  }

  if (bodyParamCount > 1) {
    diagnostics.add(
      GeneratorDiagnostic(
        severity: DiagnosticSeverity.error,
        message:
            'Method "$methodName" has $bodyParamCount body parameters. '
            'Only one @JsonBody or @FormBody is allowed per method.',
        elementName: '$className.$methodName',
      ),
    );
  }
}

void _validateReturnType(
  MethodElement method,
  String className,
  String methodName,
  List<GeneratorDiagnostic> diagnostics,
) {
  var returnType = method.returnType;

  // Unwrap Future/FutureOr.
  if (returnType.isDartAsyncFuture || returnType.isDartAsyncFutureOr) {
    returnType = (returnType as InterfaceType).typeArguments.first;
  }

  // void is always OK.
  if (returnType is VoidType) return;

  // Response is always OK.
  if (returnType is InterfaceType && returnType.element.name == 'Response') {
    return;
  }

  // Other types are fine — the emitter handles serialization.
}

void _validateUseAnnotation(
  DartObject? useValue,
  String elementName,
  List<GeneratorDiagnostic> diagnostics,
) {
  if (useValue == null) return;

  final middlewareType = useValue.getField('middleware')?.type;
  if (middlewareType == null) return;

  if (middlewareType is FunctionType) return;
  if (middlewareType is InterfaceType) {
    final isMiddlewareObj = middlewareType.allSupertypes.any(
      (s) => s.element.name == 'MiddlewareObject',
    );
    if (isMiddlewareObj) return;
  }

  diagnostics.add(
    GeneratorDiagnostic(
      severity: DiagnosticSeverity.error,
      message:
          '@Use argument must be a Middleware function or MiddlewareObject '
          'instance.',
      elementName: elementName,
      suggestion:
          'Use a function of type Handler Function(Handler) or a '
          'MiddlewareObject subclass.',
    ),
  );
}
