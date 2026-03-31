import 'dart:convert';
import 'package:relic_core/relic_core.dart';
import 'package:relic_errors/relic_errors.dart';
import 'package:test/test.dart';
import 'package:test_utils/test_utils.dart';

Request _testRequest() => testRequest(localhostUri);

void main() {
  group('ApiErrors middleware', () {
    late RelicRouter router;

    setUp(() {
      router = RelicRouter();
      router.inject(const ApiErrors());
    });

    test('catches BadRequestException and returns 400 JSON response', () async {
      router.get('/', (req) => throw const BadRequestException('invalid'));

      final result = router.lookup(Method.get, '/');
      final match = result as RouterMatch<Handler>;
      final response = await match.value(_testRequest()) as Response;

      expect(response.statusCode, 400);
      expect(response.body.bodyType?.mimeType, MimeType.json);
      final body = await response.readAsString();
      final parsed = jsonDecode(body);
      expect(parsed['statusCode'], 400);
      expect(parsed['message'], 'invalid');
    });

    test('catches NotFoundException and returns 404 JSON response', () async {
      router.get('/', (req) => throw const NotFoundException('not here'));

      final result = router.lookup(Method.get, '/');
      final match = result as RouterMatch<Handler>;
      final response = await match.value(_testRequest()) as Response;

      expect(response.statusCode, 404);
      final body = await response.readAsString();
      final parsed = jsonDecode(body);
      expect(parsed['statusCode'], 404);
      expect(parsed['message'], 'not here');
    });

    test(
      'catches InternalServerErrorException and returns 500 JSON response.',
      () async {
        router.get(
          '/',
          (req) => throw const InternalServerErrorException('crash'),
        );

        final result = router.lookup(Method.get, '/');
        final match = result as RouterMatch<Handler>;
        final response = await match.value(_testRequest()) as Response;

        expect(response.statusCode, 500);
        final body = await response.readAsString();
        final parsed = jsonDecode(body);
        expect(parsed['statusCode'], 500);
        expect(parsed['message'], 'crash');
      },
    );

    test('passes through non-HttpException responses.', () async {
      router.get('/', (req) => Response.ok(body: Body.fromString('hello')));

      final result = router.lookup(Method.get, '/');
      final match = result as RouterMatch<Handler>;
      final response = await match.value(_testRequest()) as Response;

      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, 'hello');
    });

    test('does not catch non-HttpException errors', () async {
      router.get('/', (req) => throw StateError('unrelated'));

      final result = router.lookup(Method.get, '/');
      final match = result as RouterMatch<Handler>;

      expect(
        () async => await match.value(_testRequest()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
