import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  group('Given a NoCache', () {
    late NoCache<String, int> cache;

    setUp(() {
      cache = const NoCache<String, int>();
    });

    test('when retrieving a key '
        'then it returns null', () {
      expect(cache['a'], isNull);
    });

    test('when storing a value '
        'then it cannot be retrieved', () {
      cache['a'] = 1;
      expect(cache['a'], isNull);
    });

    test('when checking length '
        'then it is always 0', () {
      cache['a'] = 1;
      cache['b'] = 2;
      expect(cache.length, equals(0));
    });
  });

  group('Given a Router (no result cache)', () {
    test('when a request path is looked up twice '
        'then routing works and the results are equal but not memoized', () {
      final router = Router<int>()..get('/a/b', 1);

      final first = router.lookupUri(Method.get, Uri.parse('/a/b'));
      final second = router.lookupUri(Method.get, Uri.parse('/a/b'));

      expect((first as RouterMatch<int>).value, equals(1));
      expect((second as RouterMatch<int>).value, equals(1));
      // No result cache: each lookup builds a fresh result.
      expect(identical(first, second), isFalse);
    });

    test('when a route is added after a lookup '
        'then the new route is found', () {
      final router = Router<int>()..get('/a/b', 1);

      expect(
        router.lookupUri(Method.get, Uri.parse('/a/c')),
        isA<PathMiss<int>>(),
      );

      router.get('/a/c', 2);
      final hit = router.lookupUri(Method.get, Uri.parse('/a/c'));
      expect((hit as RouterMatch<int>).value, equals(2));
    });
  });
}
