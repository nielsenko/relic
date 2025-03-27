import 'package:relic/relic.dart';
import 'package:relic/src/headers/header_flyweight.dart';
import 'package:relic/src/headers/parser/common_types_parser.dart';
import 'package:test/test.dart';

import '../headers_test_utils.dart';

void main() {
  group('Given direct manipulation of CustomHeaders', () {
    test('when adding new custom headers then it allows the addition', () {
      var headers = Headers.empty();
      var updatedHeaders = headers.transform(
        (mh) => mh['X-Custom-Authorization'] = ['Bearer token'],
      );

      expect(
        updatedHeaders['x-custom-authorization'],
        equals(['Bearer token']),
      );
    });

    test('when updating existing custom headers then it allows the update', () {
      var headers = CustomHeaders({
        'X-Custom-Header': ['custom-value'],
      });
      var updatedHeaders = headers.add('X-Custom-Header', ['updated-value']);

      expect(
        updatedHeaders['x-custom-header'],
        equals(['updated-value']),
      );
    });

    test('when removing custom headers then it allows the removal', () {
      var headers = CustomHeaders({
        'X-Custom-Header1': ['custom-value1'],
        'X-Custom-Header2': ['custom-value2'],
      });
      var updatedHeaders = headers.removeKey('X-Custom-Header2');

      expect(updatedHeaders['x-custom-header2'], isNull);
      expect(
        updatedHeaders['x-custom-header1'],
        equals(['custom-value1']),
      );
    });

    test(
        'when using copyWith on custom headers then it allows modifying headers',
        () {
      var headers = CustomHeaders({
        'X-Custom-Header': ['custom-value'],
      });
      var copiedHeaders = headers.copyWith(newHeaders: {
        'X-Custom-Header': ['new-value'],
        'X-Custom-Authorization': ['Bearer token'],
      });

      expect(
        copiedHeaders['x-custom-header'],
        equals(['new-value']),
      );
      expect(
        copiedHeaders['x-custom-authorization'],
        equals(['Bearer token']),
      );
    });
  });

  group('Given server request with custom headers', () {
    late RelicServer server;

    setUp(() async {
      server = await createServer(strictHeaders: false);
    });

    tearDown(() => server.close());

    const custom = HeaderFlyweight<List<String>>(
      'foo',
      HeaderDecoderMulti(parseStringList),
    );

    test(
        'when custom headers have multiple values then it combines them correctly',
        () async {
      var headers = await getServerRequestHeaders(
        server: server,
        headers: {
          'FoO': 'x,y',
          'bAr': 'z',
        },
      );
      var customHeaders = headers;

      expect(
        customHeaders['foo'],
        equals(['x,y']),
      );
      expect(
        customHeaders['bar'],
        equals(['z']),
      );
      expect(
        custom.getValueFrom(customHeaders),
        ['x', 'y'],
      );
    });

    test(
        'when custom headers have empty values then it ignores the empty values and combines non-empty ones',
        () async {
      var headers = await getServerRequestHeaders(
        server: server,
        headers: {
          'FoO': 'x',
          'bAr': 'z',
        },
      );
      var customHeaders = headers;

      expect(
        customHeaders['foo'],
        equals(['x']),
      );
      expect(
        customHeaders['bar'],
        equals(['z']),
      );
    });

    test(
        'when custom headers have multiple managed and custom values then it correctly separates and handles them',
        () async {
      var headers = await getServerRequestHeaders(
        server: server,
        headers: {
          'X-Custom-Header1': 'value1',
          'bAr': 'z',
        },
      );
      var customHeaders = headers;

      expect(
        customHeaders['x-custom-header1'],
        equals(['value1']),
      );
      expect(
        customHeaders['bar'],
        equals(['z']),
      );
    });

    test(
        'when custom headers have a normal format and multiple values then it handles all custom headers without interference',
        () async {
      var headers = await getServerRequestHeaders(
        server: server,
        headers: {
          'X-Custom-Header1': 'customValue1',
          'X-Custom-Header2': 'customValue2',
        },
      );
      var customHeaders = headers;

      expect(
        customHeaders['x-custom-header1'],
        equals(['customValue1']),
      );
      expect(
        customHeaders['x-custom-header2'],
        equals(['customValue2']),
      );
    });
  });
}
