import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  group('PathTrie backtracking inference,', () {
    group('Given a table with no literal/parameter overlap at any level,', () {
      late PathTrie<int> trie;

      setUp(() {
        trie = PathTrie<int>()
          ..add(NormalizedPath('/users/:id/items/:itemId'), 1)
          ..add(NormalizedPath('/health'), 2);
      });

      test('when inspected, '
          'then it does not need backtracking', () {
        expect(trie.needsBacktracking, isFalse);
      });

      test('when looked up, '
          'then routing still works', () {
        final result = trie.lookup(NormalizedPath('/users/7/items/9'));
        expect(result!.value, 1);
        expect(result.parameters, {
          const Symbol('id'): '7',
          const Symbol('itemId'): '9',
        });
      });

      test('when looked up with backtrack: false, '
          'then it does not throw and routes correctly', () {
        final result = trie.lookup(
          NormalizedPath('/users/7/items/9'),
          backtrack: false,
        );
        expect(result!.value, 1);
      });
    });

    group('Given a literal and a parameter overlapping at the same level,', () {
      late PathTrie<int> trie;

      setUp(() {
        trie = PathTrie<int>()
          ..add(NormalizedPath('/a/b/d'), 1)
          ..add(NormalizedPath('/a/:x/c'), 2);
      });

      test('when inspected, '
          'then it needs backtracking', () {
        expect(trie.needsBacktracking, isTrue);
      });

      test(
        'when a path takes the literal branch but only matches via the parameter branch, '
        'then backtracking finds it',
        () {
          final result = trie.lookup(NormalizedPath('/a/b/c'));
          expect(result!.value, 2);
          expect(result.parameters, {const Symbol('x'): 'b'});
        },
      );

      test(
        'when looked up with backtrack: false, '
        'then the literal branch is taken and the parameter route is not matched',
        () {
          expect(
            trie.lookup(NormalizedPath('/a/b/c'), backtrack: false),
            isNull,
          );
          // The literal route itself still resolves without backtracking.
          expect(
            trie.lookup(NormalizedPath('/a/b/d'), backtrack: false)!.value,
            1,
          );
        },
      );
    });

    group(
      'Given a parameter added under a node that already has a literal child,',
      () {
        test('when inspected, '
            'then it needs backtracking regardless of registration order', () {
          final literalFirst = PathTrie<int>()
            ..add(NormalizedPath('/a/b'), 1)
            ..add(NormalizedPath('/a/:x'), 2);
          expect(literalFirst.needsBacktracking, isTrue);

          final paramFirst = PathTrie<int>()
            ..add(NormalizedPath('/a/:x'), 1)
            ..add(NormalizedPath('/a/b'), 2);
          expect(paramFirst.needsBacktracking, isTrue);
        });
      },
    );
  });
}
