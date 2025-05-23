import '../adapter/context.dart';
import '../message/response.dart';
import 'handler.dart';

/// A typedef for [Cascade._shouldCascade].
/// The signature for the function used by [Cascade] to determine if it
/// should try the next handler based on the current [response].
/// Returns `true` if the next handler should be tried, `false` otherwise.
typedef _ShouldCascade = bool Function(Response response);

/// A helper that calls several handlers in sequence and returns the first
/// acceptable response.
///
/// By default, a response is considered acceptable if it has a status other
/// than 404 or 405; other statuses indicate that the handler understood the
/// request.
///
/// If all handlers return unacceptable responses, the final response will be
/// returned.
///
/// ```dart
///  var handler = new Cascade()
///      .add(webSocketHandler)
///      .add(staticFileHandler)
///      .add(application)
///      .handler;
/// ```
class Cascade {
  /// The function used to determine whether the cascade should continue on to
  /// the next handler.
  final _ShouldCascade _shouldCascade;

  final Cascade? _parent;
  final Handler? _handler;

  /// Creates a new, empty cascade.
  ///
  /// If [statusCodes] is passed, responses with those status codes are
  /// considered unacceptable. If [shouldCascade] is passed, responses for which
  /// it returns `true` are considered unacceptable. [statusCodes] and
  /// [shouldCascade] may not both be passed.
  Cascade(
      {final Iterable<int>? statusCodes,
      final bool Function(Response)? shouldCascade})
      : _shouldCascade = _computeShouldCascade(statusCodes, shouldCascade),
        _parent = null,
        _handler = null {
    if (statusCodes != null && shouldCascade != null) {
      throw ArgumentError('statusCodes and shouldCascade may not both be '
          'passed.');
    }
  }

  Cascade._(this._parent, this._handler, this._shouldCascade);

  /// Returns a new cascade with [handler] added to the end.
  ///
  /// [handler] will only be called if all previous handlers in the cascade
  /// return unacceptable responses.
  Cascade add(final Handler handler) =>
      Cascade._(this, handler, _shouldCascade);

  /// Exposes this cascade as a single handler.
  ///
  /// This handler will call each inner handler in the cascade until one returns
  /// an acceptable response, and return that. If no inner handlers return an
  /// acceptable response, this will return the final response.
  Handler get handler {
    final handler = _handler;
    if (handler == null) {
      throw StateError("Can't get a handler for a cascade with no inner "
          'handlers.');
    }

    return (final ctx) async {
      if (_parent!._handler == null) return handler(ctx);
      final newCtx = await _parent.handler(ctx);
      if (newCtx is ResponseContext && _shouldCascade(newCtx.response)) {
        return handler(ctx);
      }
      return newCtx;
    };
  }
}

/// Computes the [Cascade._shouldCascade] function based on the user's
/// parameters.
_ShouldCascade _computeShouldCascade(
    Iterable<int>? statusCodes, final bool Function(Response)? shouldCascade) {
  if (shouldCascade != null) return shouldCascade;
  statusCodes ??= [404, 405];
  final statusCodeSet = statusCodes.toSet();
  return (final response) => statusCodeSet.contains(response.statusCode);
}
