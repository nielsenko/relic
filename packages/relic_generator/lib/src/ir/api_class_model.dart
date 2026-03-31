import 'endpoint_model.dart';
import 'error_model.dart';

/// Represents an @Api annotated class.
class ApiClassModel {
  /// The name of the annotated class (e.g., 'UsersApi').
  final String className;

  /// The base path from @Api annotation (e.g., '/api/users').
  final String basePath;

  /// All endpoint methods in this class.
  final List<EndpointModel> endpoints;

  /// Class-level middleware from @Use annotations.
  final List<MiddlewareRef> middleware;

  /// Class-level error declarations from @Errors.
  final List<ErrorModel> errors;

  const ApiClassModel({
    required this.className,
    required this.basePath,
    required this.endpoints,
    this.middleware = const [],
    this.errors = const [],
  });
}

/// Represents a middleware reference from @Use.
/// Discriminates between function references and MiddlewareObject instances.
sealed class MiddlewareRef {
  const MiddlewareRef();
}

/// A middleware that is a function reference (Handler Function(Handler)).
class FunctionMiddlewareRef extends MiddlewareRef {
  /// The source expression as it appears in code (e.g., 'logRequests').
  final String expression;

  const FunctionMiddlewareRef({required this.expression});
}

/// A middleware that is a MiddlewareObject subclass instance.
class ObjectMiddlewareRef extends MiddlewareRef {
  /// The source expression as it appears in code (e.g., 'AuthMiddleware()').
  final String expression;

  /// The type name of the MiddlewareObject subclass.
  final String typeName;

  const ObjectMiddlewareRef({required this.expression, required this.typeName});
}
