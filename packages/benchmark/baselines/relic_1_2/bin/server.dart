// The plaintext, headers and browser routes of bin/http_load.dart on
// Relic 1.2.0, the last 1.x release, with its dart:io adapter. The route
// bodies are those of lib/src/load_app.dart, written against the 1.2.0
// API. Serves at the port in the first argument with the isolates in the
// second, and over HTTPS given a certificate chain and a key.
//
//   dart pub get
//   dart run bin/server.dart 8094 1
//   dart run ../../bin/http_load.dart --targets=relic12-io=http://127.0.0.1:8094
//   dart run bin/server.dart 8494 1 \
//       ../../../relic_native/test/certs/localhost_cert.pem \
//       ../../../relic_native/test/certs/localhost_key.pem
import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8094 : int.parse(args[0]);
  final isolates = args.length < 2 ? 1 : int.parse(args[1]);
  if (args.length == 3) throw ArgumentError('key path missing');
  final tls = args.length > 3 ? (chain: args[2], key: args[3]) : null;
  final server = await _app().run(
    // A SecurityContext cannot cross isolates, so each makes its own.
    () => IOAdapter.bind(
      InternetAddress.loopbackIPv4,
      port: port,
      shared: isolates > 1,
      context: tls == null
          ? null
          : (SecurityContext()
              ..useCertificateChain(tls.chain)
              ..usePrivateKey(tls.key)),
    ),
    noOfIsolates: isolates,
  );
  stdout.writeln('ready $pid');
  await ProcessSignal.sigterm.watch().first;
  await server.close();
}

RelicApp _app() {
  // A Body is read once, so every response gets its own.
  Body hello() => Body.fromString('Hello, World!');
  return RelicApp()
    ..get('/plaintext', (req) => Response.ok(body: hello()))
    ..get('/headers', _headers)
    ..get('/browser', _browser);
}

/// What a page handler reads: the agent, the languages and a cookie.
Response _headers(Request req) {
  final agent = req.headers.userAgent ?? '';
  final languages = req.headers.acceptLanguage?.values.length ?? 0;
  final session = req.headers.cookie?.cookies
      .where((c) => c.name == 'session')
      .firstOrNull
      ?.value;
  return Response.ok(
    body: Body.fromString('${agent.length} $languages ${session?.length ?? 0}'),
  );
}

/// A page handler on a real browser head.
///
/// It reads the host, a cookie and the validator, and answers with etag,
/// cache-control and 1 KB of JSON, or 304 when the validator matches.
Response _browser(Request req) {
  final host = req.headers.host?.host;
  final session = req.headers.cookie?.cookies
      .where((c) => c.name == 'session')
      .firstOrNull
      ?.value;
  final matched =
      req.headers.ifNoneMatch?.etags.any((e) => e.value == _etag.value) ??
      false;
  if (matched) {
    return Response.notModified(headers: Headers.build((h) => h.etag = _etag));
  }
  return Response.ok(
    headers: Headers.build(
      (h) => h
        ..etag = _etag
        ..cacheControl = CacheControlHeader(privateCache: true, maxAge: 60),
    ),
    body: Body.fromString(
      '{"host":${jsonEncode(host)},"session":${jsonEncode(session)},'
      '"items":$_items}',
      mimeType: MimeType.json,
    ),
  );
}

const _etag = ETagHeader(value: 'relic-browser-1');

/// The items encoded once, so the request only joins strings.
final _items = jsonEncode([
  for (var i = 0; i < 20; i++)
    {
      'id': i,
      'name': 'item $i',
      'tags': ['new', 'sale'],
      'price': 100 + i,
    },
]);
