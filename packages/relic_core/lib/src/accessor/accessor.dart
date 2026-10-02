import 'package:meta/meta.dart';

import '../headers/codec.dart';

/// A read-only accessor for extracting typed values from a keyed storage.
///
/// This is a flyweight pattern where the accessor defines how to decode
/// a value, and an [AccessorStateMixin] holds the actual data.
///
/// Type parameters:
/// - [T]: The decoded type
/// - [K]: The key type used to identify values in storage
/// - [R]: The raw storage type
abstract class ReadOnlyAccessor<T extends Object, K, R> {
  /// The key used to identify this value in storage.
  final K key;

  const ReadOnlyAccessor(this.key);

  /// Decodes the raw value into the typed value. Throws for a value that
  /// does not decode.
  T decode(final R raw);
}

/// A [ReadOnlyAccessor] that decodes with a function.
///
/// The base for the path, query and form accessors, whose decoder is a
/// plain function such as `int.parse`.
abstract class FunctionAccessor<T extends Object, K, R>
    extends ReadOnlyAccessor<T, K, R> {
  final Decoder<T, R> _decode;

  const FunctionAccessor(super.key, this._decode);

  @override
  T decode(final R raw) => _decode(raw);
}

/// Typed reads over a keyed storage, with a cache of decoded values.
///
/// Shared by path, query and form parameters and by headers, so every one
/// of them reads the same way: [call] for the value or null, [get] when
/// the value must be there, and [tryGet] when a bad value is as good as
/// none.
mixin AccessorStateMixin<K, R> {
  /// Cache for decoded values, keyed by (accessor, raw) pair. The raw key
  /// is the raw value, or whatever else the value was decoded from, such as
  /// a byte view. Accessor instances remain distinct via their default
  /// identity-based `==`.
  Map<(ReadOnlyAccessor<dynamic, K, R>, Object), Object?>? _cache;

  /// The raw value for [key], or null when absent.
  R? lookup(final K key);

  /// Returns the raw value for the given [accessor], or `null` if not present.
  R? operator [](final ReadOnlyAccessor<dynamic, K, R> accessor) =>
      lookup(accessor.key);

  /// Returns the decoded value for the given [accessor].
  ///
  /// Throws if the value is missing or if decoding fails.
  T get<T extends Object>(final ReadOnlyAccessor<T, K, R> accessor) =>
      call(accessor) ??
      (throw StateError('Missing value for key: ${accessor.key}'));

  /// Returns the decoded value for the given [accessor], or `null` if missing.
  ///
  /// Throws if decoding fails.
  T? call<T extends Object>(final ReadOnlyAccessor<T, K, R> accessor) {
    final rawValue = lookup(accessor.key);
    if (rawValue == null) return null;
    return decodeCached(accessor, rawValue, () => accessor.decode(rawValue));
  }

  /// The value [decode] produces for [accessor] from [raw], decoded once
  /// per (accessor, raw) pair.
  @protected
  T decodeCached<T extends Object>(
    final ReadOnlyAccessor<T, K, R> accessor,
    final Object raw,
    final T Function() decode,
  ) => ((_cache ??= {})[(accessor, raw)] ??= decode()) as T;

  /// Returns the decoded value for the given [accessor], or `null` if missing
  /// or if decoding fails.
  T? tryGet<T extends Object>(final ReadOnlyAccessor<T, K, R> accessor) {
    try {
      return call(accessor);
    } catch (_) {
      return null;
    }
  }

  /// Takes over every decoded value [other] holds.
  ///
  /// A value assigned through an accessor stays the very object that was
  /// assigned, on the headers built from that mutable, instead of being
  /// decoded again from its encoded form.
  @protected
  void adoptCache(final AccessorStateMixin<K, R> other) {
    final adopted = other._cache;
    if (adopted == null || adopted.isEmpty) return;
    (_cache ??= {}).addAll(adopted);
  }

  /// Records [value] as the decoded form of [raw] for [accessor], so a
  /// value that was just encoded is not decoded again on read. [raw] is
  /// whatever [call] will decode from for this accessor.
  @protected
  void prime<T extends Object>(
    final ReadOnlyAccessor<T, K, R> accessor,
    final Object raw,
    final T value,
  ) {
    (_cache ??= {})[(accessor, raw)] = value;
  }
}

/// Holds the externalized state for [ReadOnlyAccessor] instances in a map.
class AccessorState<K, R> with AccessorStateMixin<K, R> {
  /// The raw key-value storage.
  final Map<K, R> raw;

  /// Creates a new accessor state with the given raw values.
  AccessorState(this.raw);

  @override
  R? lookup(final K key) => raw[key];
}

extension RawEx<K, R> on Map<K, R> {
  /// A non-nullable lookup of [key]
  ///
  /// Throws a [StateError] if the value is missing.
  R get(final K key) =>
      this[key] ?? (throw StateError('Missing value for key: $key'));
}
