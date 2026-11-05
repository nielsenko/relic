// The plaintext and headers routes of bin/http_load.dart on a bare
// dart:io HttpServer, with no framework, for what dart:io's sockets and
// HTTP layer cost on their own. Serves at the port in the first argument
// on one isolate. It imports nothing outside the SDK, so it needs no
// package configuration.
//
//   dart baselines/dartio/server.dart 18098
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 18098 : int.parse(args[0]);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.defaultResponseHeaders.clear();
  server.listen(_handle);
  stdout.writeln('ready $pid');
  await ProcessSignal.sigterm.watch().first;
  await server.close(force: true);
}

final _text = ContentType('text', 'plain', charset: 'utf-8');

void _handle(HttpRequest request) {
  switch (request.uri.path) {
    case '/plaintext':
      _send(request.response, 'Hello, World!');
    case '/headers':
      // What a page handler reads: the agent, the languages and a cookie.
      final headers = request.headers;
      final agent = headers.value(HttpHeaders.userAgentHeader) ?? '';
      final languages = (headers[HttpHeaders.acceptLanguageHeader] ?? const [])
          .expand((v) => v.split(','))
          .length;
      final session = request.cookies
          .where((c) => c.name == 'session')
          .firstOrNull
          ?.value;
      _send(
        request.response,
        '${agent.length} $languages ${session?.length ?? 0}',
      );
    default:
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
  }
}

void _send(HttpResponse response, String body) {
  final bytes = utf8.encode(body);
  response
    ..headers.contentType = _text
    ..contentLength = bytes.length
    ..add(bytes)
    ..close();
}
