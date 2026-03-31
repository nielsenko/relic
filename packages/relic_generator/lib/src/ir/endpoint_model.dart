import 'api_class_model.dart';
import 'error_model.dart';
import 'parameter_model.dart';

/// HTTP methods supported by endpoint annotations.
enum HttpMethod { get, post, put, delete, patch }

/// Represents a single endpoint method annotated with @Get, @Post, etc.
class EndpointModel {
  /// The method name in the source class (e.g., 'list', 'getById').
  final String methodName;

  /// The HTTP method (get, post, put, delete, patch).
  final HttpMethod httpMethod;

  /// The relative path from the method annotation (e.g., '/', '/:id').
  final String path;

  /// The return type as a string (e.g., `Future<List<User>>`).
  final String returnType;

  /// The inner type unwrapped from Future (e.g., `List<User>` from `Future<List<User>>`).
  final String resolvedReturnType;

  /// Whether the return type is void.
  final bool isVoid;

  /// Whether the method is async (returns Future).
  final bool isAsync;

  /// Parameters of this endpoint method.
  final List<ParameterModel> parameters;

  /// Method-level middleware from @Use annotations.
  final List<MiddlewareRef> middleware;

  /// Method-level error declarations from @Errors.
  final List<ErrorModel> errors;

  /// Custom status code from @Status annotation, if any.
  final int? statusCode;

  const EndpointModel({
    required this.methodName,
    required this.httpMethod,
    required this.path,
    required this.returnType,
    required this.resolvedReturnType,
    required this.isVoid,
    required this.isAsync,
    required this.parameters,
    this.middleware = const [],
    this.errors = const [],
    this.statusCode,
  });
}
