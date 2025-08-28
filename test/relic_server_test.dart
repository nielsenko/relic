import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import 'headers/headers_test_utils.dart';
import 'util/fake_adapter/fake_adapter_utils.dart';
import 'util/test_util.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await createHarness();
  });

  tearDown(() => harness.close());

  group('Given a server', () {
    test('when a valid HTTP request is made '
        'then it serves the request using the mounted handler', () async {
      await harness.mount(syncHandler);
      final response = await harness.client.read(harness.url);
      expect(response, equals('Hello from /'));
    });

    test('when a malformed HTTP request is made '
        'then it returns a 400 Bad Request response', () async {
      // This test requires real network IO - malformed URLs are rejected
      // before reaching FakeAdapter
      final server = await testServe(syncHandler);
      addTearDown(server.close);

      final rs = await http.get(
        Uri.parse('${server.url}/%D0%C2%BD%A8%CE%C4%BC%FE%BC%D0.zip'),
      );
      expect(rs.statusCode, 400);
      expect(rs.body, 'Bad Request');
    });

    test('when no handler is mounted initially '
        'then it delays requests until a handler is mounted', () async {
      // This test requires direct adapter control
      final adapter = await IOAdapter.bind(InternetAddress.loopbackIPv4);
      final port = adapter.port;
      final delayedResponse = http.read(Uri.http('localhost:$port'));
      final server = RelicServer(() => adapter);
      await server.mountAndStart(asyncHandler);
      await expectLater(delayedResponse, completion(equals('Hello from /')));
      await server.close();
    });
  });
}
