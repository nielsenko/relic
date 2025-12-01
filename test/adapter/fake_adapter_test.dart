import 'package:relic/fake_adapter.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

void main() {
  group('FakeAdapter', () {
    late FakeAdapter adapter;
    late RelicServer server;
    late FakeHttpClient client;

    setUp(() {
      adapter = FakeAdapter();
      server = RelicServer(() => adapter);
      client = FakeHttpClient(adapter);
    });

    tearDown(() => server.close());

    test('handles simple GET request', () async {
      await server.mountAndStart((final req) {
        return Response.ok(body: Body.fromString('Hello from ${req.url.path}'));
      });

      final response = await client.get(Uri.parse('http://localhost/test'));

      expect(response.statusCode, equals(200));
      expect(response.body, equals('Hello from /test'));
    });

    test('handles POST request with body', () async {
      await server.mountAndStart((final req) async {
        final body = await req.body.read().toList();
        final text = String.fromCharCodes(body.expand((final c) => c));
        return Response.ok(body: Body.fromString('Received: $text'));
      });

      final response = await client.post(
        Uri.parse('http://localhost/api'),
        body: 'test data',
      );

      expect(response.statusCode, equals(200));
      expect(response.body, equals('Received: test data'));
    });

    test('handles headers', () async {
      await server.mountAndStart((final req) {
        final auth = req.headers['authorization']?.first ?? 'none';
        return Response.ok(body: Body.fromString('Auth: $auth'));
      });

      final response = await client.get(
        Uri.parse('http://localhost/secure'),
        headers: {'authorization': 'Bearer token123'},
      );

      expect(response.statusCode, equals(200));
      expect(response.body, equals('Auth: Bearer token123'));
    });

    test('returns error responses', () async {
      await server.mountAndStart((final req) {
        return Response.notFound(body: Body.fromString('Not found'));
      });

      final response = await client.get(Uri.parse('http://localhost/missing'));

      expect(response.statusCode, equals(404));
      expect(response.body, equals('Not found'));
    });

    test('handles multiple sequential requests', () async {
      var counter = 0;
      await server.mountAndStart((final req) {
        counter++;
        return Response.ok(body: Body.fromString('Request #$counter'));
      });

      final r1 = await client.get(Uri.parse('http://localhost/'));
      final r2 = await client.get(Uri.parse('http://localhost/'));
      final r3 = await client.get(Uri.parse('http://localhost/'));

      expect(r1.body, equals('Request #1'));
      expect(r2.body, equals('Request #2'));
      expect(r3.body, equals('Request #3'));
    });
  });

  group('TestHarness', () {
    for (final adapterType in [AdapterType.fake]) {
      // Only test fake adapter to avoid network in unit tests
      group('[$adapterType]', () {
        late TestHarness harness;

        setUp(() async {
          harness = await TestHarness.create(adapterType);
        });

        tearDown(() => harness.close());

        test('serves requests', () async {
          await harness.mount((final req) {
            return Response.ok(body: Body.fromString('Hello!'));
          });

          final response = await harness.client.get(harness.url);

          expect(response.statusCode, equals(200));
          expect(response.body, equals('Hello!'));
        });

        test('urlFor builds correct paths', () async {
          await harness.mount((final req) {
            return Response.ok(body: Body.fromString('Path: ${req.url.path}'));
          });

          final response = await harness.client.get(
            harness.urlFor('/api/test'),
          );

          expect(response.statusCode, equals(200));
          expect(response.body, equals('Path: /api/test'));
        });
      });
    }
  });
}
