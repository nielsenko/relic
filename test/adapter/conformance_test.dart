/// Conformance tests that run against both FakeAdapter and IOAdapter.
///
/// This demonstrates how to write adapter-agnostic tests that can verify
/// conformance across different adapter implementations.
library;

import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../util/fake_adapter/fake_adapter_utils.dart';

void main() {
  // Run the same tests against both adapter types
  for (final adapterType in AdapterType.values) {
    group('Adapter conformance [$adapterType]', () {
      late TestHarness harness;

      setUp(() async {
        harness = await TestHarness.create(adapterType);
      });

      tearDown(() => harness.close());

      group('HTTP methods', () {
        test('handles GET requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.get));
            return Response.ok(body: Body.fromString('GET OK'));
          });

          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(200));
          expect(response.body, equals('GET OK'));
        });

        test('handles POST requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.post));
            return Response.ok(body: Body.fromString('POST OK'));
          });

          final response = await harness.client.post(harness.url);
          expect(response.statusCode, equals(200));
          expect(response.body, equals('POST OK'));
        });

        test('handles PUT requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.put));
            return Response.ok(body: Body.fromString('PUT OK'));
          });

          final response = await harness.client.put(harness.url);
          expect(response.statusCode, equals(200));
          expect(response.body, equals('PUT OK'));
        });

        test('handles PATCH requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.patch));
            return Response.ok(body: Body.fromString('PATCH OK'));
          });

          final response = await harness.client.patch(harness.url);
          expect(response.statusCode, equals(200));
          expect(response.body, equals('PATCH OK'));
        });

        test('handles DELETE requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.delete));
            return Response.ok(body: Body.fromString('DELETE OK'));
          });

          final response = await harness.client.delete(harness.url);
          expect(response.statusCode, equals(200));
          expect(response.body, equals('DELETE OK'));
        });

        test('handles HEAD requests', () async {
          await harness.mount((final req) {
            expect(req.method, equals(Method.head));
            return Response.ok();
          });

          final response = await harness.client.head(harness.url);
          expect(response.statusCode, equals(200));
        });
      });

      group('Status codes', () {
        test('returns 200 OK', () async {
          await harness.mount((final req) => Response.ok());
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(200));
        });

        test('returns 201 Created', () async {
          await harness.mount((final req) => Response(201));
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(201));
        });

        test('returns 204 No Content', () async {
          await harness.mount((final req) => Response(204));
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(204));
        });

        test('returns 400 Bad Request', () async {
          await harness.mount((final req) => Response.badRequest());
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(400));
        });

        test('returns 404 Not Found', () async {
          await harness.mount((final req) => Response.notFound());
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(404));
        });

        test('returns 500 Internal Server Error', () async {
          await harness.mount((final req) => Response.internalServerError());
          final response = await harness.client.get(harness.url);
          expect(response.statusCode, equals(500));
        });
      });

      group('Request paths', () {
        test('handles root path', () async {
          await harness.mount((final req) {
            return Response.ok(body: Body.fromString(req.url.path));
          });

          final response = await harness.client.get(harness.urlFor('/'));
          expect(response.body, equals('/'));
        });

        test('handles nested paths', () async {
          await harness.mount((final req) {
            return Response.ok(body: Body.fromString(req.url.path));
          });

          final response = await harness.client.get(
            harness.urlFor('/api/v1/users'),
          );
          expect(response.body, equals('/api/v1/users'));
        });

        test('handles query parameters', () async {
          await harness.mount((final req) {
            final name = req.url.queryParameters['name'] ?? 'unknown';
            return Response.ok(body: Body.fromString('Hello, $name'));
          });

          final url = harness
              .urlFor('/greet')
              .replace(queryParameters: {'name': 'World'});
          final response = await harness.client.get(url);
          expect(response.body, equals('Hello, World'));
        });
      });

      group('Request body', () {
        test('receives string body', () async {
          await harness.mount((final req) async {
            final chunks = await req.body.read().toList();
            final body = String.fromCharCodes(chunks.expand((final c) => c));
            return Response.ok(body: Body.fromString('Echo: $body'));
          });

          final response = await harness.client.post(
            harness.url,
            body: 'test data',
          );
          expect(response.body, equals('Echo: test data'));
        });
      });

      group('Response body', () {
        test('returns string body', () async {
          await harness.mount((final req) {
            return Response.ok(body: Body.fromString('Hello, World!'));
          });

          final response = await harness.client.get(harness.url);
          expect(response.body, equals('Hello, World!'));
        });

        test('returns empty body', () async {
          await harness.mount((final req) => Response.ok());
          final response = await harness.client.get(harness.url);
          expect(response.body, isEmpty);
        });

        test('returns JSON body', () async {
          await harness.mount((final req) {
            return Response.ok(
              body: Body.fromString('{"key":"value"}', mimeType: MimeType.json),
            );
          });

          final response = await harness.client.get(harness.url);
          expect(response.body, equals('{"key":"value"}'));
        });
      });

      group('Async handlers', () {
        test('handles async handler', () async {
          await harness.mount((final req) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return Response.ok(body: Body.fromString('Async response'));
          });

          final response = await harness.client.get(harness.url);
          expect(response.body, equals('Async response'));
        });
      });
    });
  }
}
