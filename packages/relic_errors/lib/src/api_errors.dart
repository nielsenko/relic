import 'dart:convert';

import 'package:codable_dart/standard.dart';
import 'package:relic_core/relic_core.dart';

import 'http_exception.dart';

/// Error-handling middleware that catches [HttpException]s thrown by handlers
/// and converts them to JSON error responses.
///
/// Mount at the app level to handle all errors:
/// ```dart
/// final app = RelicRouter();
/// app.inject(const ApiErrors());
/// ```
class ApiErrors implements RouterInjectable {
  const ApiErrors();

  @override
  void injectIn(RelicRouter router) {
    router.use('/', _middleware);
  }

  Handler _middleware(Handler next) => (Request req) async {
    try {
      return await next(req);
    } on HttpException catch (e) {
      final encoded = e.toMap();
      final jsonBody = jsonEncode(encoded);
      return Response(
        e.statusCode,
        body: Body.fromString(jsonBody, mimeType: MimeType.json),
      );
    }
  };
}
