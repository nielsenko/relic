import 'dart:convert';
import 'dart:typed_data';

import '../../../relic.dart';
import '../../context/result.dart' show RequestInternal;
import '../connection_info.dart';
import 'fake_adapter.dart';

/// An HTTP client that communicates directly with a [FakeAdapter] in memory.
///
/// This client bypasses all network traffic, enabling fast, deterministic
/// tests. It implements a simple HTTP client interface similar to `package:http`.
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
class FakeHttpClient {
  final FakeAdapter _adapter;

  /// Creates a [FakeHttpClient] that sends requests to the given [adapter].
  FakeHttpClient(this._adapter);

  /// Sends an HTTP GET request to the given [url].
  Future<FakeClientResponse> get(
    final Uri url, {
    final Map<String, String>? headers,
  }) => send(FakeClientRequest(Method.get, url, headers: headers));

  /// Sends an HTTP POST request to the given [url].
  Future<FakeClientResponse> post(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
    final Encoding encoding = utf8,
  }) => send(
    FakeClientRequest(
      Method.post,
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    ),
  );

  /// Sends an HTTP PUT request to the given [url].
  Future<FakeClientResponse> put(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
    final Encoding encoding = utf8,
  }) => send(
    FakeClientRequest(
      Method.put,
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    ),
  );

  /// Sends an HTTP PATCH request to the given [url].
  Future<FakeClientResponse> patch(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
    final Encoding encoding = utf8,
  }) => send(
    FakeClientRequest(
      Method.patch,
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    ),
  );

  /// Sends an HTTP DELETE request to the given [url].
  Future<FakeClientResponse> delete(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
    final Encoding encoding = utf8,
  }) => send(
    FakeClientRequest(
      Method.delete,
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    ),
  );

  /// Sends an HTTP HEAD request to the given [url].
  Future<FakeClientResponse> head(
    final Uri url, {
    final Map<String, String>? headers,
  }) => send(FakeClientRequest(Method.head, url, headers: headers));

  /// Sends the given [request] and returns a [FakeClientResponse].
  Future<FakeClientResponse> send(final FakeClientRequest request) async {
    final relicRequest = _buildRequest(request);
    final adapterRequest = FakeAdapterRequest(relicRequest);

    final fakeResponse = await _adapter.handleRequest(adapterRequest);

    return FakeClientResponse(
      statusCode: fakeResponse.statusCode,
      headers: _headersToMap(fakeResponse.headers),
      bodyBytes: Uint8List.fromList(fakeResponse.bodyBytes),
    );
  }

  /// Sends a request and returns the response body as a string.
  Future<String> read(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await get(url, headers: headers);
    return response.body;
  }

  /// Sends a request and returns the response body as bytes.
  Future<Uint8List> readBytes(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await get(url, headers: headers);
    return response.bodyBytes;
  }

  Request _buildRequest(final FakeClientRequest request) {
    final headers = Headers.build((final mh) {
      request.headers?.forEach((final key, final value) {
        mh[key] = [value];
      });
    });

    Body body;
    if (request.body == null) {
      body = Body.empty();
    } else if (request.body is String) {
      body = Body.fromString(request.body as String);
    } else if (request.body is List<int>) {
      body = Body.fromData(Uint8List.fromList(request.body as List<int>));
    } else if (request.body is Map) {
      // Encode as form data
      final encoded =
          Uri(
            queryParameters: (request.body as Map).map(
              (final k, final v) => MapEntry(k.toString(), v.toString()),
            ),
          ).query;
      body = Body.fromString(encoded);
    } else {
      body = Body.fromString(request.body.toString());
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
      request.method,
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

/// A request to be sent by [FakeHttpClient].
class FakeClientRequest {
  final Method method;
  final Uri url;
  final Map<String, String>? headers;
  final Object? body;
  final Encoding encoding;

  FakeClientRequest(
    this.method,
    this.url, {
    this.headers,
    this.body,
    this.encoding = utf8,
  });
}

/// A response from [FakeHttpClient].
class FakeClientResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  FakeClientResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  /// The response body as a string.
  String get body => utf8.decode(bodyBytes);

  /// Whether the request was successful (status code 2xx).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
