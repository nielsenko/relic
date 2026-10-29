import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:relic/relic.dart';

/// The routes of bin/http_load.dart, so bin/load_serve.dart can serve them
/// on their own for a profiler or a load tool started elsewhere.
RelicApp loadApp() {
  final random = Random(1);
  // A Body is read once, so every response gets its own.
  Body hello() => Body.fromString('Hello, World!');
  return RelicApp()
    ..get('/plaintext', (req) => Response.ok(body: hello()))
    ..get(
      '/json',
      (req) => Response.ok(
        body: Body.fromString(
          jsonEncode({'message': 'Hello, World!'}),
          mimeType: MimeType.json,
        ),
      ),
    )
    ..get('/headers', (req) {
      // What a page handler reads: the agent, the languages and a cookie.
      final agent = req.headers.userAgent ?? '';
      final languages = req.headers.acceptLanguage?.values.length ?? 0;
      final session = req.headers.cookie?.cookies
          .where((c) => c.name == 'session')
          .firstOrNull
          ?.value;
      return Response.ok(
        body: Body.fromString(
          '${agent.length} $languages ${session?.length ?? 0}',
        ),
      );
    })
    ..get('/browser', (req) => _browser(req, _concatBody))
    ..get('/browser-json', (req) => _browser(req, _jsonEncodeBody))
    ..get('/browser-utf8', (req) => _browser(req, _utf8JsonBody))
    ..post('/read-string', (req) async {
      final doc = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      return _count((doc['items'] as List<dynamic>).length);
    })
    ..get('/alloc', (req) {
      // Garbage per request: a few thousand short-lived objects and a
      // 64 KiB string built from them.
      final parts = List.generate(4000, (i) => 'item-$i-${i * 7}');
      final text = parts.join(',');
      return Response.ok(body: Body.fromString(text.substring(0, 1024)));
    })
    ..get('/mixed', (req) async {
      // One request in a hundred waits on something slow.
      if (random.nextInt(100) == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return Response.ok(body: hello());
    });
}

/// A page handler on a real browser head.
///
/// It reads the host, a cookie and the validator, and answers with etag,
/// cache-control and 1 KB of JSON built by [body], or 304 when the
/// validator matches.
Response _browser(
  Request req,
  Body Function(String? host, String? session) body,
) {
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
    body: body(host, session),
  );
}

const _etag = ETagHeader(value: 'relic-browser-1');

/// The items encoded once, so the request only joins strings.
Body _concatBody(String? host, String? session) => Body.fromString(
  '{"host":${jsonEncode(host)},"session":${jsonEncode(session)},'
  '"items":$_items}',
  mimeType: MimeType.json,
);

/// The whole document through jsonEncode on every request.
Body _jsonEncodeBody(String? host, String? session) => Body.fromString(
  jsonEncode({'host': host, 'session': session, 'items': _itemMaps()}),
  mimeType: MimeType.json,
);

/// The whole document as bytes from dart:convert's JsonUtf8Encoder.
Body _utf8JsonBody(String? host, String? session) => Body.fromData(
  JsonUtf8Encoder().convert({
        'host': host,
        'session': session,
        'items': _itemMaps(),
      })
      as Uint8List,
  mimeType: MimeType.json,
);

List<Map<String, Object>> _itemMaps() => [
  for (var i = 0; i < 20; i++)
    {
      'id': i,
      'name': 'item $i',
      'tags': ['new', 'sale'],
      'price': 100 + i,
    },
];

final _items = jsonEncode(_itemMaps());

/// The document the read routes are posted: the browser document with a
/// fixed host and session, 1.2 KB.
final String readDocument = jsonEncode({
  'host': 'example.com',
  'session': 'a3f9c2e1b7d4f6a8c0e2d4b6f8a1c3e5',
  'items': _itemMaps(),
});

/// The answer of a read route: the item count, so the response costs the
/// same on each and the body read is what differs.
Response _count(int items) => Response.ok(body: Body.fromString('$items'));
