import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:relic/relic.dart';
import 'package:relic/src/adapter/connection_info.dart';
import 'package:relic/src/context/result.dart' show RequestInternal;

import 'fake_adapter.dart';

/// An HTTP client that communicates directly with a [FakeAdapter] in memory.
///
/// This client extends [http.BaseClient], making it a drop-in replacement for
/// the standard `package:http` client. It bypasses all network traffic,
/// enabling fast, deterministic tests.
///
/// Example:
/// ```dart
/// final adapter = FakeAdapter();
/// final server = RelicServer(() => adapter);
/// await server.mountAndStart(myHandler);
///
/// final client = FakeHttpClient(adapter);
/// final response = await client.get(Uri.parse('http://localhost/test'));
/// print(response.body); // Response from myHandler
/// ```
class FakeHttpClient extends http.BaseClient {
  final FakeAdapter _adapter;

  /// Creates a [FakeHttpClient] that sends requests to the given [adapter].
  FakeHttpClient(this._adapter);

  @override
  Future<http.StreamedResponse> send(final http.BaseRequest request) async {
    final relicRequest = _buildRelicRequest(request);
    final adapterRequest = FakeAdapterRequest(relicRequest);

    final fakeResponse = await _adapter.handleRequest(adapterRequest);

    return http.StreamedResponse(
      Stream.value(Uint8List.fromList(fakeResponse.bodyBytes)),
      fakeResponse.statusCode,
      headers: _headersToMap(fakeResponse.headers),
      request: request,
    );
  }

  Request _buildRelicRequest(final http.BaseRequest request) {
    final headers = Headers.build((final mh) {
      request.headers.forEach((final key, final value) {
        mh[key] = [value];
      });
    });

    Body body;
    if (request is http.Request) {
      final bodyBytes = request.bodyBytes;
      if (bodyBytes.isEmpty) {
        body = Body.empty();
      } else {
        body = Body.fromData(bodyBytes);
      }
    } else if (request is http.MultipartRequest) {
      // For multipart, we'd need more complex handling
      // For now, treat as empty body
      body = Body.empty();
    } else {
      body = Body.empty();
    }

    // Ensure URL is absolute
    var url = request.url;
    if (!url.hasScheme) {
      url = url.replace(scheme: 'http');
    }
    if (!url.hasAuthority) {
      url = url.replace(host: 'localhost');
    }

    return RequestInternal.create(
      Method.parse(request.method),
      url,
      Object(), // token
      headers: headers,
      body: body,
      connectionInfo: ConnectionInfo(
        remote: SocketAddress(address: IPv4Address.loopback, port: 12345),
        localPort: 0,
      ),
    );
  }

  Map<String, String> _headersToMap(final Headers headers) {
    final map = <String, String>{};
    for (final name in headers.keys) {
      final values = headers[name];
      if (values != null && values.isNotEmpty) {
        map[name] = values.join(', ');
      }
    }
    return map;
  }
}
