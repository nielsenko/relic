import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';

import 'fake_adapter/fake_adapter.dart';
import 'fake_adapter/fake_http_client.dart';

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
/// adapter implementations to verify conformance. Since [FakeHttpClient]
/// extends [http.BaseClient], both adapter types use the same `http.Client`
/// interface.
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
  final http.Client _client;

  TestHarness._({
    required this.adapterType,
    required final RelicServer server,
    required final http.Client client,
  }) : _server = server,
       _client = client;

  /// Creates a test harness for the given [adapterType].
  static Future<TestHarness> create(final AdapterType adapterType) async {
    switch (adapterType) {
      case AdapterType.fake:
        final adapter = FakeAdapter();
        final server = RelicServer(() => adapter);
        final client = FakeHttpClient(adapter);
        return TestHarness._(
          adapterType: adapterType,
          server: server,
          client: client,
        );

      case AdapterType.io:
        final server = RelicServer(
          () => IOAdapter.bind(io.InternetAddress.loopbackIPv4, port: 0),
        );
        final client = http.Client();
        return TestHarness._(
          adapterType: adapterType,
          server: server,
          client: client,
        );
    }
  }

  /// The HTTP client for making requests.
  ///
  /// This is an [http.Client] which works with both adapter types.
  /// For [AdapterType.fake], this is a [FakeHttpClient].
  /// For [AdapterType.io], this is a standard [http.Client].
  http.Client get client => _client;

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
}
