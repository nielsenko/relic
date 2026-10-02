// A package that depends on relic_headers alone can build a response store
// and read any HeaderStore through the base class.
import 'dart:typed_data';

import 'package:relic_headers/relic_headers.dart';

void main() {
  final response = MapHeaderStore()
    ..set(HeaderName.contentType, ['text/plain; charset=utf-8'])
    ..add(HeaderName.setCookie, 'a=1')
    ..add(HeaderName.setCookie, 'b=2');

  print(response.value(HeaderName.contentType));
  print(response.values(HeaderName.setCookie).join(' | '));

  // Adapters hand over whatever store they have. Read it through the base
  // class without caring which one.
  describe(response);
  describe(_FixedStore());

  // Known names are found in raw bytes without allocating.
  final head = Uint8List.fromList('Content-Length: 12'.codeUnits);
  print(HeaderName.lookupBytes(head, 0, 14)); // content-length
}

void describe(final HeaderStore store) {
  store.forEach((final name, final value) => print('$name: $value'));
}

/// A store over something that is not a map, to show the four members an
/// implementer provides.
final class _FixedStore extends HeaderStore {
  @override
  Iterable<HeaderName> get names => const [HeaderName.server];

  @override
  Iterable<String> values(final HeaderName name) =>
      name == HeaderName.server ? const ['fixed/1.0'] : const [];

  @override
  Uint8List? rawValue(final HeaderName name) => null;

  @override
  HeaderStore detach() => this;
}
