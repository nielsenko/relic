import 'header_name.dart';
import 'map_header_store.dart';

/// Read access to the header fields of a message.
///
/// A base class, not an interface: implementers extend it and provide the
/// two abstract members. Everything else has a default, so members can be
/// added here later without breaking a store in another package. Override
/// a default when the store can do better, for example [value] on a store
/// that already caches its first value.
///
/// Names are matched case-insensitively through [HeaderName]. Values are
/// text.
abstract base class HeaderStore {
  const HeaderStore();

  /// Every distinct name, in the order it first appears.
  Iterable<HeaderName> get names;

  /// Every value for [name], in order. Empty when [name] is absent.
  ///
  /// The same object comes back for the same name while the store is not
  /// modified, so a caller may cache by identity.
  Iterable<String> values(final HeaderName name);

  /// The number of name and value pairs.
  int get fieldCount {
    var count = 0;
    for (final name in names) {
      count += values(name).length;
    }
    return count;
  }

  /// The first value for [name], or null.
  String? value(final HeaderName name) {
    final all = values(name);
    return all.isEmpty ? null : all.first;
  }

  bool contains(final HeaderName name) => values(name).isNotEmpty;

  bool get isEmpty => names.isEmpty;

  bool get isNotEmpty => names.isNotEmpty;

  /// Visits every name and value pair, in order. The slow path: it
  /// materializes every value.
  void forEach(final void Function(HeaderName name, String value) visit) {
    for (final name in names) {
      for (final value in values(name)) {
        visit(name, value);
      }
    }
  }

  /// An empty mutable store of the kind the adapter behind this store
  /// handles fastest in a response.
  ///
  /// A caller with a request in hand gets the efficient store from the
  /// request's headers, and nothing has to hand it a factory.
  MutableHeaderStore newMutable() => MapHeaderStore();

  /// [newMutable] with this store's fields.
  MutableHeaderStore toMutable() {
    final copy = newMutable();
    for (final name in names) {
      copy.set(name, values(name));
    }
    return copy;
  }
}

/// A [HeaderStore] that can be written.
///
/// Every writer rejects a value with CR, LF or NUL, the characters that
/// would end a header field or the header block and hand the rest of the
/// message to whoever supplied the value. The rest of the field-value
/// grammar is checked by typed headers, when the header is read.
abstract base class MutableHeaderStore extends HeaderStore {
  const MutableHeaderStore();

  /// Replaces every value for [name] with [values]. An empty [values]
  /// removes the field.
  void set(final HeaderName name, final Iterable<String> values);

  /// Appends [value] to the values for [name].
  void add(final HeaderName name, final String value);

  void remove(final HeaderName name);

  void clear();

  /// Throws [FormatException] when [value] carries CR, LF or NUL.
  static void checkValue(final HeaderName name, final String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 0x0D || c == 0x0A || c == 0x00) {
        throw FormatException(
          'Header "${name.lower}" value must not contain CR, LF or NUL',
          value,
          i,
        );
      }
    }
  }
}
