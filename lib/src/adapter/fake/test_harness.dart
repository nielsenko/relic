import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../relic.dart';
import '../io/io_adapter.dart';
import 'fake_adapter.dart';
import 'fake_http_client.dart';

/// A unified HTTP client interface for testing.
///
/// This interface abstracts the differences between [FakeHttpClient] and
/// `package:http` [http.Client], allowing tests to be written once and run
/// with either adapter type.
abstract class TestClient {
  Future<TestResponse> get(final Uri url, {final Map<String, String>? headers});
  Future<TestResponse> post(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  });
  Future<TestResponse> put(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  });
  Future<TestResponse> patch(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  });
  Future<TestResponse> delete(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  });
  Future<TestResponse> head(
    final Uri url, {
    final Map<String, String>? headers,
  });

  Future<String> read(final Uri url, {final Map<String, String>? headers});
  Future<Uint8List> readBytes(
    final Uri url, {
    final Map<String, String>? headers,
  });

  void close();
}

/// A unified response type for testing.
class TestResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  TestResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  String get body => utf8.decode(bodyBytes);
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// A [TestClient] implementation backed by [FakeHttpClient].
class FakeTestClient implements TestClient {
  final FakeHttpClient _client;

  FakeTestClient(final FakeAdapter adapter) : _client = FakeHttpClient(adapter);

  @override
  Future<TestResponse> get(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await _client.get(url, headers: headers);
    return _convert(response);
  }

  @override
  Future<TestResponse> post(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.post(url, headers: headers, body: body);
    return _convert(response);
  }

  @override
  Future<TestResponse> put(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.put(url, headers: headers, body: body);
    return _convert(response);
  }

  @override
  Future<TestResponse> patch(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.patch(url, headers: headers, body: body);
    return _convert(response);
  }

  @override
  Future<TestResponse> delete(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.delete(url, headers: headers, body: body);
    return _convert(response);
  }

  @override
  Future<TestResponse> head(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await _client.head(url, headers: headers);
    return _convert(response);
  }

  @override
  Future<String> read(final Uri url, {final Map<String, String>? headers}) =>
      _client.read(url, headers: headers);

  @override
  Future<Uint8List> readBytes(
    final Uri url, {
    final Map<String, String>? headers,
  }) => _client.readBytes(url, headers: headers);

  @override
  void close() {
    // FakeHttpClient doesn't need explicit closing
  }

  TestResponse _convert(final FakeClientResponse response) {
    return TestResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: response.bodyBytes,
    );
  }
}

/// A [TestClient] implementation backed by `package:http`.
class IOTestClient implements TestClient {
  final http.Client _client = http.Client();

  @override
  Future<TestResponse> get(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await _client.get(url, headers: headers);
    return _convert(response);
  }

  @override
  Future<TestResponse> post(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.post(
      url,
      headers: headers,
      body:
          body is String || body is List<int> || body is Map
              ? body
              : body?.toString(),
    );
    return _convert(response);
  }

  @override
  Future<TestResponse> put(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.put(
      url,
      headers: headers,
      body:
          body is String || body is List<int> || body is Map
              ? body
              : body?.toString(),
    );
    return _convert(response);
  }

  @override
  Future<TestResponse> patch(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.patch(
      url,
      headers: headers,
      body:
          body is String || body is List<int> || body is Map
              ? body
              : body?.toString(),
    );
    return _convert(response);
  }

  @override
  Future<TestResponse> delete(
    final Uri url, {
    final Map<String, String>? headers,
    final Object? body,
  }) async {
    final response = await _client.delete(
      url,
      headers: headers,
      body:
          body is String || body is List<int> || body is Map
              ? body
              : body?.toString(),
    );
    return _convert(response);
  }

  @override
  Future<TestResponse> head(
    final Uri url, {
    final Map<String, String>? headers,
  }) async {
    final response = await _client.head(url, headers: headers);
    return _convert(response);
  }

  @override
  Future<String> read(final Uri url, {final Map<String, String>? headers}) =>
      _client.read(url, headers: headers);

  @override
  Future<Uint8List> readBytes(
    final Uri url, {
    final Map<String, String>? headers,
  }) => _client.readBytes(url, headers: headers);

  @override
  void close() => _client.close();

  TestResponse _convert(final http.Response response) {
    return TestResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: response.bodyBytes,
    );
  }
}

/// Configuration for which adapter type to use in tests.
enum AdapterType {
  /// Use [FakeAdapter] with in-memory requests (no network traffic).
  fake,

  /// Use [IOAdapter] with real network requests.
  io,
}

/// A test harness that abstracts adapter selection for conformance testing.
///
/// This harness allows you to write tests once and run them against different
/// adapter implementations to verify conformance.
///
/// Example:
/// ```dart
/// void main() {
///   for (final adapterType in AdapterType.values) {
///     group('[$adapterType]', () {
///       late TestHarness harness;
///
///       setUp(() async {
///         harness = await TestHarness.create(adapterType);
///       });
///
///       tearDown(() => harness.close());
///
///       test('responds with 200', () async {
///         await harness.mount((req) => Response.ok(
///           body: Body.fromString('Hello!'),
///         ));
///
///         final response = await harness.client.get(harness.url);
///         expect(response.statusCode, 200);
///         expect(response.body, 'Hello!');
///       });
///     });
///   }
/// }
/// ```
class TestHarness {
  final AdapterType adapterType;
  final RelicServer _server;
  final TestClient _client;
  final FakeAdapter? _fakeAdapter;

  TestHarness._({
    required this.adapterType,
    required final RelicServer server,
    required final TestClient client,
    final FakeAdapter? fakeAdapter,
  }) : _server = server,
       _client = client,
       _fakeAdapter = fakeAdapter;

  /// Creates a test harness for the given [adapterType].
  static Future<TestHarness> create(final AdapterType adapterType) async {
    switch (adapterType) {
      case AdapterType.fake:
        final adapter = FakeAdapter();
        final server = RelicServer(() => adapter);
        final client = FakeTestClient(adapter);
        return TestHarness._(
          adapterType: adapterType,
          server: server,
          client: client,
          fakeAdapter: adapter,
        );

      case AdapterType.io:
        final server = RelicServer(
          () => IOAdapter.bind(io.InternetAddress.loopbackIPv4, port: 0),
        );
        final client = IOTestClient();
        return TestHarness._(
          adapterType: adapterType,
          server: server,
          client: client,
        );
    }
  }

  /// The HTTP client for making requests.
  TestClient get client => _client;

  /// The underlying server.
  RelicServer get server => _server;

  /// The base URL for requests.
  ///
  /// For [AdapterType.fake], this returns a localhost URL.
  /// For [AdapterType.io], this returns the actual bound URL.
  Uri get url {
    switch (adapterType) {
      case AdapterType.fake:
        return Uri.parse('http://localhost/');
      case AdapterType.io:
        return Uri.http('localhost:${_server.port}');
    }
  }

  /// Builds a URL path relative to the server's base URL.
  Uri urlFor(final String path) {
    switch (adapterType) {
      case AdapterType.fake:
        return Uri.parse('http://localhost$path');
      case AdapterType.io:
        return Uri.http('localhost:${_server.port}', path);
    }
  }

  /// Mounts a handler and starts the server.
  Future<void> mount(final Handler handler) async {
    await _server.mountAndStart(handler);
  }

  /// Returns connection information from the server.
  Future<ConnectionsInfo> connectionsInfo() => _server.connectionsInfo();

  /// Closes the harness, releasing all resources.
  Future<void> close() async {
    _client.close();
    await _server.close();
  }

  /// Access to the [FakeAdapter] if using [AdapterType.fake].
  ///
  /// Throws [StateError] if using [AdapterType.io].
  FakeAdapter get fakeAdapter {
    if (_fakeAdapter == null) {
      throw StateError('FakeAdapter is only available with AdapterType.fake');
    }
    return _fakeAdapter;
  }
}
