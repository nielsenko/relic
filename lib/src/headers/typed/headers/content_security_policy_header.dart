import "package:relic/relic.dart";
import 'package:relic/src/headers/extension/string_list_extensions.dart';

/// A class representing the HTTP Content-Security-Policy (CSP) header.
///
/// This class manages CSP directives, providing functionality to parse, add,
/// remove, and generate CSP header values.
final class ContentSecurityPolicyHeader {
  static const codec =
      HeaderCodec.single(ContentSecurityPolicyHeader.parse, __encode);
  static List<String> __encode(ContentSecurityPolicyHeader value) =>
      [value._encode()];

  /// A list of CSP directives.
  final List<ContentSecurityPolicyDirective> directives;

  /// Constructs a [ContentSecurityPolicyHeader] instance with the specified
  /// directives.
  const ContentSecurityPolicyHeader({required this.directives});

  /// Parses a CSP header value and returns a [ContentSecurityPolicyHeader]
  /// instance.
  ///
  /// This method splits the header value by semicolons, trims each directive,
  /// and processes the directive and its values.
  factory ContentSecurityPolicyHeader.parse(String value) {
    final splitValues = value.splitTrimAndFilterUnique(separator: ';');
    if (splitValues.isEmpty) {
      throw FormatException('Value cannot be empty');
    }

    var directiveSeparator = RegExp(r'\s+');
    final directives = splitValues.map<ContentSecurityPolicyDirective>((part) {
      final directiveParts = part.split(directiveSeparator);
      final name = directiveParts.first;
      final values = directiveParts.skip(1).toList();
      return ContentSecurityPolicyDirective(
        name: name,
        values: values,
      );
    }).toList();

    return ContentSecurityPolicyHeader(directives: directives);
  }

  /// Converts the [ContentSecurityPolicyHeader] instance into a string
  /// representation suitable for HTTP headers.

  String _encode() {
    return directives.map((directive) => directive._encode()).join('; ');
  }

  @override
  String toString() {
    return 'ContentSecurityPolicyHeader(directives: $directives)';
  }
}

/// A class representing a single CSP directive.
class ContentSecurityPolicyDirective {
  /// The name of the directive (e.g., `default-src`, `script-src`).
  final String name;

  /// The values associated with the directive (e.g., `'self'`,
  /// `https://example.com`).
  final Iterable<String> values;

  /// Constructs a [ContentSecurityPolicyDirective] instance with the specified
  /// name and values.
  ContentSecurityPolicyDirective({
    required this.name,
    required this.values,
  });

  /// Converts the [ContentSecurityPolicyDirective] instance into a string
  /// representation.
  String _encode() => '$name ${values.join(' ')}';

  @override
  String toString() {
    return 'ContentSecurityPolicyDirective(name: $name, values: $values)';
  }
}
