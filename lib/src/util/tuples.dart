/// Extends a 1-element record (tuple `(T,)`) with an `add` method.
extension Tuple1<T> on (T,) {
  /// Adds an element [u] of type [U] to this 1-element record.
  ///
  /// Returns a new 2-element record `(T, U)`.
  ///
  /// Example:
  /// ```dart
  /// final tuple1 = (5,);
  /// final tuple2 = tuple1.add('hello'); // tuple2 is (5, 'hello')
  /// ```
  (T, U) add<U>(final U u) => (this.$1, u);
}

/// Extends a 2-element record (tuple `(T1, T2)`) with an `add` method.
extension Tuple2<T1, T2> on (T1, T2) {
  /// Adds an element [u] of type [U] to this 2-element record.
  ///
  /// Returns a new 3-element record `(T1, T2, U)`.
  ///
  /// Example:
  /// ```dart
  /// final tuple2 = (5, 'hello');
  /// final tuple3 = tuple2.add(true); // tuple3 is (5, 'hello', true)
  /// ```
  (T1, T2, U) add<U>(final U u) => (this.$1, this.$2, u);
}

/// Extends a 3-element record (tuple `(T1, T2, T3)`) with an `add` method.
extension Tuple3<T1, T2, T3> on (T1, T2, T3) {
  /// Adds an element [u] of type [U] to this 3-element record.
  ///
  /// Returns a new 4-element record `(T1, T2, T3, U)`.
  ///
  /// Example:
  /// ```dart
  /// final tuple3 = (5, 'hello', true);
  /// final tuple4 = tuple3.add(10.5); // tuple4 is (5, 'hello', true, 10.5)
  /// ```
  (T1, T2, T3, U) add<U>(final U u) => (this.$1, this.$2, this.$3, u);
}

/// Extends a 4-element record (tuple `(T1, T2, T3, T4)`) with an `add` method.
extension Tuple4<T1, T2, T3, T4> on (T1, T2, T3, T4) {
  /// Adds an element [u] of type [U] to this 4-element record.
  ///
  /// Returns a new 5-element record `(T1, T2, T3, T4, U)`.
  ///
  /// Example:
  /// ```dart
  /// final tuple4 = (5, 'hello', true, 10.5);
  /// final tuple5 = tuple4.add('world'); // tuple5 is (5, 'hello', true, 10.5, 'world')
  /// ```
  (T1, T2, T3, T4, U) add<U>(final U u) =>
      (this.$1, this.$2, this.$3, this.$4, u);
}
