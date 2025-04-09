import "package:relic/relic.dart";
import 'package:http_parser/http_parser.dart';
import 'etag_header.dart';

/// A class representing the HTTP `If-Range` header.
///
/// The `If-Range` header can contain either an HTTP date or an ETag.
final class IfRangeHeader {
  static const codec = HeaderCodec.single(IfRangeHeader.parse, __encode);
  static List<String> __encode(IfRangeHeader value) => [value._encode()];

  /// The HTTP date if the `If-Range` header contains a date.
  final DateTime? lastModified;

  /// The ETag if the `If-Range` header contains an ETag.
  final ETagHeader? etag;

  /// Constructs an [IfRangeHeader] instance with either a date or an ETag.
  ///
  /// Either [lastModified] or [etag] must be non-null.
  IfRangeHeader({
    this.lastModified,
    this.etag,
  }) {
    if (lastModified == null && etag == null) {
      throw FormatException('Either date or etag must be provided');
    }
  }

  /// Parses the `If-Range` header value and returns an [IfRangeHeader] instance.
  ///
  /// Determines if the value is an ETag or a date and creates the appropriate instance.
  factory IfRangeHeader.parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Value cannot be empty');
    }

    // Check if the value is a valid ETag
    if (ETagHeader.isValidETag(trimmed)) {
      return IfRangeHeader(etag: ETagHeader.parse(trimmed));
    }

    try {
      final parsedDate = parseHttpDate(trimmed);
      return IfRangeHeader(lastModified: parsedDate);
    } catch (_) {
      throw FormatException('Invalid format');
    }
  }

  /// Converts the [IfRangeHeader] instance into a string representation
  /// suitable for HTTP headers.

  String _encode() =>
      lastModified != null ? formatHttpDate(lastModified!) : etag!.encode();

  @override
  String toString() {
    return 'IfRangeHeader(lastModified: $lastModified, etag: $etag)';
  }
}
