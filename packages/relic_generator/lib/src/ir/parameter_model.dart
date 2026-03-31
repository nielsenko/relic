/// The source of a parameter value.
enum ParameterSource {
  /// From a path segment (@Path).
  path,

  /// From a query string parameter (@Query).
  query,

  /// From an HTTP header (@Header).
  header,

  /// From the JSON request body (@JsonBody).
  jsonBody,

  /// From a form-encoded request body (@FormBody).
  formBody,

  /// The raw Request object (@Req).
  request,
}

/// Represents a parameter of an endpoint method.
class ParameterModel {
  /// The parameter name in the source code (e.g., 'id', 'limit').
  final String name;

  /// The Dart type as a string (e.g., 'int', 'String', 'User').
  final String type;

  /// Whether the parameter is nullable.
  final bool isNullable;

  /// Whether the parameter is required (non-nullable without default).
  final bool isRequired;

  /// The source of the parameter value.
  final ParameterSource source;

  /// The explicit name from the annotation, if provided.
  /// For @Path('user_id'), this would be 'user_id'.
  /// When null, the parameter name is used.
  final String? sourceName;

  /// Whether the parameter has a default value in the source code.
  final bool hasDefault;

  /// The default value expression as a string, if any.
  final String? defaultValueCode;

  const ParameterModel({
    required this.name,
    required this.type,
    required this.isNullable,
    required this.isRequired,
    required this.source,
    this.sourceName,
    this.hasDefault = false,
    this.defaultValueCode,
  });

  /// The effective name used for parameter extraction.
  /// Uses [sourceName] if provided, otherwise [name].
  String get effectiveName => sourceName ?? name;
}
