import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../docs/strict_validation_docs.dart';
import '../headers_test_utils.dart';

/// Reference: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Transfer-Encoding
/// For more details on header validation behavior, see the [HeaderValidationDocs] class.
void main() {
  group('Given a Transfer-Encoding header with validation', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer();
    });

    tearDown(() => server.close());

    test(
      'when no Transfer-Encoding header is passed then it should return null',
      () async {
        final headers = await getServerRequestHeaders(
          server: server,
          touchHeaders: (final h) => h.transferEncoding,
          headers: {},
        );

        expect(headers.transferEncoding, isNull);
      },
    );
  });
}
