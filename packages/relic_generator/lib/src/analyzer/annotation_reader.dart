import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Checks if an element has a specific annotation from relic_annotations.
bool hasAnnotation(Element element, String annotationName) {
  return element.metadata.annotations.any((m) {
    final annotElement = m.element;
    if (annotElement is ConstructorElement) {
      return annotElement.enclosingElement.name == annotationName;
    }
    return false;
  });
}

/// Gets the DartObject for a specific annotation, or null.
DartObject? getAnnotation(Element element, String annotationName) {
  for (final metadata in element.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == annotationName) {
      return metadata.computeConstantValue();
    }
  }
  return null;
}

/// Gets all annotations of a specific type.
List<DartObject> getAnnotations(Element element, String annotationName) {
  final results = <DartObject>[];
  for (final metadata in element.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == annotationName) {
      final value = metadata.computeConstantValue();
      if (value != null) results.add(value);
    }
  }
  return results;
}

/// Checks if a type is assignable to `Handler Function(Handler)` (Middleware).
///
/// Verifies the type is a function with exactly one parameter where both the
/// parameter type and return type are function types (since `Handler` is a
/// typedef for `FutureOr<Response> Function(Request)`).
bool isFunctionMiddleware(DartType type) {
  if (type is FunctionType) {
    if (type.normalParameterTypes.length != 1) return false;
    final paramType = type.normalParameterTypes.first;
    final returnType = type.returnType;
    return paramType is FunctionType && returnType is FunctionType;
  }
  return false;
}

/// Checks if a type is a subtype of MiddlewareObject.
bool isMiddlewareObjectSubtype(DartType type) {
  if (type is InterfaceType) {
    return type.allSupertypes.any((s) => s.element.name == 'MiddlewareObject');
  }
  return false;
}
