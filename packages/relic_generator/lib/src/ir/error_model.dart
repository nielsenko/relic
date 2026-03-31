/// Represents a declared error type from @Errors annotation.
class ErrorModel {
  /// The type name of the HttpException subclass (e.g., 'NotFoundError').
  final String typeName;

  /// The HTTP status code associated with this error, if discoverable.
  final int? statusCode;

  const ErrorModel({required this.typeName, this.statusCode});
}
