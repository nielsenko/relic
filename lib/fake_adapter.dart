/// In-memory adapter for testing without network traffic.
///
/// This library provides [FakeAdapter] and [FakeHttpClient] which work in
/// concert to bypass all network traffic in tests. This enables fast,
/// deterministic testing of Relic applications.
///
/// Example:
/// ```dart
/// import 'package:relic/fake_adapter.dart';
/// import 'package:relic/relic.dart';
///
/// void main() {
///   test('handles requests', () async {
///     final adapter = FakeAdapter();
///     final server = RelicServer(() => adapter);
///     await server.mountAndStart((req) => Response.ok(
///       body: Body.fromString('Hello!'),
///     ));
///
///     final client = FakeHttpClient(adapter);
///     final response = await client.get(Uri.parse('http://localhost/'));
///     expect(response.body, equals('Hello!'));
///
///     await server.close();
///   });
/// }
/// ```
library;

export 'src/adapter/fake/fake_adapter.dart';
export 'src/adapter/fake/fake_http_client.dart';
export 'src/adapter/fake/test_harness.dart';
