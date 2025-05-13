import 'dart:collection';

/// A Least Recently Used (LRU) cache implementation. Using double buffering to
/// reduce overhead (at the expense of precision).
///
/// Keeps a fixed number of items ([_coldCapacity]). When the cache is full and a new
/// item is added, the least recently used item is evicted. Accessing an item
/// (get or update) marks it as the most recently used.
final class LruCache<K, V> {
  final int _hotCapacity;
  final int _coldCapacity;

  var _hot = HashMap<K, V>();
  // ignore: prefer_collection_literals
  final _cold = LinkedHashMap<K, V>();

  LruCache._(this._hotCapacity, this._coldCapacity) {
    RangeError.checkNotNegative(_coldCapacity, '_coldCapacity');
    RangeError.checkValueInInterval(
      _hotCapacity,
      0,
      _coldCapacity,
      '_hotCapacity',
    );
    // print('_hotCapacity: $_hotCapacity, _coldCapacity: $_coldCapacity');
  }

  /// Creates an LRU cache with the specified maximum size.
  ///
  /// Throws an [RangeError] if [maxSize] is not positive.
  factory LruCache(final int maxSize, [final double hotRatio = 0.1]) {
    RangeError.checkNotNegative(maxSize, 'maxSize');
    final hotCapacity = (maxSize * hotRatio).toInt();
    final coldCapacity = maxSize - hotCapacity;
    return LruCache._(hotCapacity, coldCapacity);
  }

  /// Retrieves the value associated with [key].
  ///
  /// Returns null if the key is not found. Accessing the key marks it as the most
  /// recently used item.
  V? operator [](final K key) {
    // Check hot buffer first (no reordering needed)
    final hotValue = _hot[key];
    if (hotValue != null) {
      return hotValue;
    }

    final coldValue = _cold[key];
    if (coldValue != null) {
      // Promote to hot buffer without modifying cache
      this[key] = coldValue;
    }
    return coldValue;
  }

  /// Associates [value] with [key] in the cache.
  ///
  /// If the key already exists, its value is updated. Adding or updating a key
  /// marks it as the most recently used item. If adding the item exceeds the cache
  /// capacity, the least recently used item is evicted.
  void operator []=(final K key, final V value) {
    // Always put in hot buffer first
    _hot[key] = value;

    // If hot buffer gets too big, flush to cold
    if (_hot.length >= _hotCapacity) {
      _flushHotToCold();
    }
  }

  void _flushHotToCold() {
    // Move all hot items as recent item in cache
    for (final entry in _hot.entries) {
      _cold.remove(entry.key);
      _cold[entry.key] = entry.value;
    }

    // Create new hot buffer. GC can claim old one in one go
    _hot = HashMap<K, V>();

    // Trim by evicting oldest entries from cold cache,
    // if we've exceeded max size
    var keysToRemove = _cold.length - _coldCapacity;
    while (keysToRemove-- > 0) {
      _cold.remove(_cold.keys.first);
    }
  }

  /// Returns the current number of items in the cache.
  int get length => _hot.length + _cold.length;
}
