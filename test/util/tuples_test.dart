import 'package:test/test.dart';
import 'package:relic/src/util/tuples.dart';

void main() {
  group('Tuple1 Extension', () {
    test(
        'Given a 1-element tuple and a value, '
        'when add is called, '
        'then it should return a 2-element tuple with the new value appended',
        () {
      // Arrange
      const initialTuple = (1,);
      const valueToAdd = 'hello';
      const expectedTuple = (1, 'hello');

      // Act
      final resultTuple = initialTuple.add(valueToAdd);

      // Assert
      expect(resultTuple, equals(expectedTuple));
      expect(resultTuple.$1, equals(initialTuple.$1));
      expect(resultTuple.$2, equals(valueToAdd));
    });
  });

  group('Tuple2 Extension', () {
    test(
        'Given a 2-element tuple and a value, '
        'when add is called, '
        'then it should return a 3-element tuple with the new value appended',
        () {
      // Arrange
      const initialTuple = (1, 'hello');
      const valueToAdd = true;
      const expectedTuple = (1, 'hello', true);

      // Act
      final resultTuple = initialTuple.add(valueToAdd);

      // Assert
      expect(resultTuple, equals(expectedTuple));
      expect(resultTuple.$1, equals(initialTuple.$1));
      expect(resultTuple.$2, equals(initialTuple.$2));
      expect(resultTuple.$3, equals(valueToAdd));
    });
  });

  group('Tuple3 Extension', () {
    test(
        'Given a 3-element tuple and a value, '
        'when add is called, '
        'then it should return a 4-element tuple with the new value appended',
        () {
      // Arrange
      const initialTuple = (1, 'hello', true);
      const valueToAdd = 3.14;
      const expectedTuple = (1, 'hello', true, 3.14);

      // Act
      final resultTuple = initialTuple.add(valueToAdd);

      // Assert
      expect(resultTuple, equals(expectedTuple));
      expect(resultTuple.$1, equals(initialTuple.$1));
      expect(resultTuple.$2, equals(initialTuple.$2));
      expect(resultTuple.$3, equals(initialTuple.$3));
      expect(resultTuple.$4, equals(valueToAdd));
    });
  });

  group('Tuple4 Extension', () {
    test(
        'Given a 4-element tuple and a value, '
        'when add is called, '
        'then it should return a 5-element tuple with the new value appended',
        () {
      // Arrange
      const initialTuple = (1, 'hello', true, 3.14);
      final valueToAdd = DateTime(2023);
      final expectedTuple = (1, 'hello', true, 3.14, DateTime(2023));

      // Act
      final resultTuple = initialTuple.add(valueToAdd);

      // Assert
      expect(resultTuple, equals(expectedTuple));
      expect(resultTuple.$1, equals(initialTuple.$1));
      expect(resultTuple.$2, equals(initialTuple.$2));
      expect(resultTuple.$3, equals(initialTuple.$3));
      expect(resultTuple.$4, equals(initialTuple.$4));
      expect(resultTuple.$5, equals(valueToAdd));
    });
  });
}
