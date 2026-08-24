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
}
