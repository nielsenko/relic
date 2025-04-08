import "package:relic/relic.dart";

/// A class representing the HTTP Sec-Fetch-Site header.
///
/// This header indicates the relationship between the origin of the request
/// initiator and the origin of the requested resource.
final class SecFetchSiteHeader {
  static const codec = HeaderCodec.single(SecFetchSiteHeader.parse, encode);
  static List<String> encode(SecFetchSiteHeader value) =>
      [value.toHeaderString()];

  /// The site value of the request.
  final String site;

  /// Private constructor for [SecFetchSiteHeader].
  const SecFetchSiteHeader._(this.site);

  /// Predefined site values.
  static const _sameOrigin = 'same-origin';
  static const _sameSite = 'same-site';
  static const _crossSite = 'cross-site';
  static const _none = 'none';

  static const sameOrigin = SecFetchSiteHeader._(_sameOrigin);
  static const sameSite = SecFetchSiteHeader._(_sameSite);
  static const crossSite = SecFetchSiteHeader._(_crossSite);
  static const none = SecFetchSiteHeader._(_none);

  /// Parses a [value] and returns the corresponding [SecFetchSiteHeader] instance.
  /// If the value does not match any predefined types, it returns a custom instance.
  factory SecFetchSiteHeader.parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Value cannot be empty');
    }

    switch (trimmed) {
      case _sameOrigin:
        return sameOrigin;
      case _sameSite:
        return sameSite;
      case _crossSite:
        return crossSite;
      case _none:
        return none;
      default:
        throw FormatException('Invalid value');
    }
  }

  /// Converts the [SecFetchSiteHeader] instance into a string representation
  /// suitable for HTTP headers.

  String toHeaderString() => site;

  @override
  String toString() {
    return 'SecFetchSiteHeader(value: $site)';
  }
}
