import 'dart:io';

import 'package:relic/relic.dart';
import 'package:relic/src/adapter/context.dart';
import 'package:relic/src/middleware/routing_middleware.dart';

/// A simple 'Hello World' server
Future<void> main() async {
  // Setup router
  final router = Router<Handler>()..get('/user/:name/age/:age', hello);

  // Setup a handler.
  //
  // A [Handler] is function consuming and producing [RequestContext]s,
  // but if you are mostly concerned with converting [Request]s to [Response]s
  // (known as a [Responder] in relic parlor) you can use [respondWith] to
  // wrap a [Responder] into a [Handler]

  final body = Body.fromString("Sorry, that doesn't compute");
  final inner = respondWith((final _) => Response.notFound(body: body));

  // What is really goind on, whatever syntax we use
  final handler0 = logRequests()(routeWith(router)(inner));

  final handler1 = logRequests() // same, but use compose to avoid nesting
      .compose(routeWith(router))
      .apply(inner);

  final handler2 = inner // same, but build inside-out
      .pipe(routeWith(router))
      .pipe(logRequests());

  // same result, less flexible approach (inherited from shelf)
  final handler3 = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(routeWith(router))
      .addHandler(inner);

  final handler = handler3; // <-- choose
  // Start the server with the handler
  await serve(handler, InternetAddress.anyIPv4, 8080);

  // Check the _example_ directory for other examples.
}

ResponseContext hello(final RequestContext ctx) {
  final name = ctx.pathParameters[#name];
  final age = int.parse(ctx.pathParameters[#age]!);

  return (ctx as RespondableContext).withResponse(Response.ok(
      body: Body.fromString('Hello $name! To think you are $age years old.')));
}
