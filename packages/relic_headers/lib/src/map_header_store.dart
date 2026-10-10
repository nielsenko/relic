import 'header_name.dart';
import 'header_store.dart';

/// The reference [MutableHeaderStore]: a map from name to values.
///
/// This is what a response is built in, and what any package uses that
/// wants a header map and nothing more.
final class MapHeaderStore extends MutableHeaderStore {
  final _fields = <HeaderName, List<String>>{};

  MapHeaderStore();

  /// A store with [fields]. Keys are looked up with [HeaderName.lookup].
  factory MapHeaderStore.from(final Map<String, Iterable<String>> fields) {
    final store = MapHeaderStore();
    for (final MapEntry(:key, :value) in fields.entries) {
      store.set(HeaderName.lookup(key), value);
    }
    return store;
  }

  @override
  Iterable<HeaderName> get names => _fields.keys;

  @override
  Iterable<String> values(final HeaderName name) =>
      _fields[name] ?? const <String>[];

  @override
  bool contains(final HeaderName name) => _fields.containsKey(name);

  @override
  int get fieldCount {
    var count = 0;
    for (final values in _fields.values) {
      count += values.length;
    }
    return count;
  }

  @override
  void set(final HeaderName name, final Iterable<String> values) {
    final copy = List<String>.unmodifiable(values);
    if (copy.isEmpty) {
      _fields.remove(name);
      return;
    }
    for (final value in copy) {
      MutableHeaderStore.checkValue(name, value);
    }
    _fields[name] = copy;
  }

  @override
  void add(final HeaderName name, final String value) {
    MutableHeaderStore.checkValue(name, value);
    _fields[name] = List.unmodifiable([...?_fields[name], value]);
  }

  @override
  void remove(final HeaderName name) => _fields.remove(name);

  @override
  void clear() => _fields.clear();

  @override
  MutableHeaderStore toMutable() {
    final copy = MapHeaderStore();
    copy._fields.addAll(_fields);
    return copy;
  }
}
