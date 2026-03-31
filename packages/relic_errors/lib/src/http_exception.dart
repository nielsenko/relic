import 'package:codable_dart/core.dart';

/// Abstract base class for HTTP exceptions that can be thrown in handlers
/// and caught by the [ApiErrors] middleware.
abstract class HttpException implements Exception, SelfEncodable {
  /// The HTTP status code for this exception.
  int get statusCode;

  /// A human-readable error message.
  String get message;

  const HttpException();

  @override
  void encode(Encoder encoder) {
    final keyed = encoder.encodeKeyed();
    keyed.encodeInt('statusCode', statusCode);
    keyed.encodeString('message', message);
    keyed.end();
  }

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// A [Codable] for decoding [HttpException] from serialized data.
///
/// Decodes based on `statusCode` field, returning the appropriate concrete subtype.
class HttpExceptionCodable extends SelfCodable<HttpException> {
  const HttpExceptionCodable();

  @override
  HttpException decode(Decoder decoder) {
    final mapped = decoder.decodeMapped();
    final statusCode = mapped.decodeInt('statusCode');
    final message = mapped.decodeString('message');

    return switch (statusCode) {
      400 => BadRequestException(message),
      401 => UnauthorizedException(message),
      403 => ForbiddenException(message),
      404 => NotFoundException(message),
      409 => ConflictException(message),
      410 => GoneException(message),
      500 => InternalServerErrorException(message),
      503 => ServiceUnavailableException(message),
      _ => _GenericHttpException(statusCode, message),
    };
  }
}

class _GenericHttpException extends HttpException {
  @override
  final int statusCode;
  @override
  final String message;

  const _GenericHttpException(this.statusCode, this.message);
}

/// 400 Bad Request
class BadRequestException extends HttpException {
  @override
  int get statusCode => 400;
  @override
  final String message;

  const BadRequestException(this.message);
}

/// 401 Unauthorized
class UnauthorizedException extends HttpException {
  @override
  int get statusCode => 401;
  @override
  final String message;

  const UnauthorizedException(this.message);
}

/// 403 Forbidden
class ForbiddenException extends HttpException {
  @override
  int get statusCode => 403;
  @override
  final String message;

  const ForbiddenException(this.message);
}

/// 404 Not Found
class NotFoundException extends HttpException {
  @override
  int get statusCode => 404;
  @override
  final String message;

  const NotFoundException(this.message);
}

/// 409 Conflict
class ConflictException extends HttpException {
  @override
  int get statusCode => 409;
  @override
  final String message;

  const ConflictException(this.message);
}

/// 410 Gone
class GoneException extends HttpException {
  @override
  int get statusCode => 410;
  @override
  final String message;

  const GoneException(this.message);
}

/// 500 Internal Server Error
class InternalServerErrorException extends HttpException {
  @override
  int get statusCode => 500;
  @override
  final String message;

  const InternalServerErrorException(this.message);
}

/// 503 Service Unavailable
class ServiceUnavailableException extends HttpException {
  @override
  int get statusCode => 503;
  @override
  final String message;

  const ServiceUnavailableException(this.message);
}
