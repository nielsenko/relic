import "package:relic/relic.dart";
import 'package:relic/src/headers/extension/string_list_extensions.dart';

/// Base class for ETag-based conditional headers (If-Match and If-None-Match).
abstract class ETagConditionHeader {
  /// The list of ETags to match against.
  final List<ETagHeader> etags;

  /// Whether this is a wildcard match (*).
  final bool isWildcard;

  /// Creates an [ETagConditionHeader] with specific ETags.
  const ETagConditionHeader.etags(this.etags) : isWildcard = false;

  /// Creates an [ETagConditionHeader] with wildcard matching.
  const ETagConditionHeader.wildcard()
      : etags = const [],
        isWildcard = true;

  /// Converts the header instance to its string representation.
  String toHeaderString() {
    if (isWildcard) return '*';
    return etags.map((e) => e.toHeaderString()).join(', ');
  }
}

/// A class representing the HTTP If-Match header.
final class IfMatchHeader extends ETagConditionHeader {
  static const codec = HeaderCodec(IfMatchHeader.parse, _encode);
  static List<String> _encode(IfMatchHeader value) => [value.toHeaderString()];

  /// Creates an [IfMatchHeader] with specific ETags.
  const IfMatchHeader.etags(super.etags) : super.etags();

  /// Creates an [IfMatchHeader] with wildcard matching.
  const IfMatchHeader.wildcard() : super.wildcard();

  /// Parses the If-Match header value.
  factory IfMatchHeader.parse(Iterable<String> values) {
    var splitValues = values.splitTrimAndFilterUnique();
    if (splitValues.isEmpty) {
      throw FormatException('Value cannot be empty');
    }

    if (splitValues.length == 1 && splitValues.first == '*') {
      return const IfMatchHeader.wildcard();
    }

    if (splitValues.length > 1 && splitValues.contains('*')) {
      throw FormatException('Wildcard (*) cannot be used with other values');
    }

    final parsedEtags = splitValues.map((value) {
      if (!ETagHeader.isValidETag(value)) {
        throw FormatException('Invalid ETag format');
      }
      return ETagHeader.parse(value);
    }).toList();

    return IfMatchHeader.etags(parsedEtags);
  }

  @override
  String toString() => 'IfMatchHeader(etags: $etags, isWildcard: $isWildcard)';
}

/// A class representing the HTTP If-None-Match header.
final class IfNoneMatchHeader extends ETagConditionHeader {
  static const codec = HeaderCodec(IfNoneMatchHeader.parse, _encode);
  static List<String> _encode(IfNoneMatchHeader value) =>
      [value.toHeaderString()];

  /// Creates an [IfNoneMatchHeader] with specific ETags.
  const IfNoneMatchHeader.etags(super.etags) : super.etags();

  /// Creates an [IfNoneMatchHeader] with wildcard matching.
  const IfNoneMatchHeader.wildcard() : super.wildcard();

  /// Parses the If-None-Match header value.
  factory IfNoneMatchHeader.parse(Iterable<String> values) {
    var splitValues = values.splitTrimAndFilterUnique();
    if (splitValues.isEmpty) {
      throw FormatException('Value cannot be empty');
    }

    if (splitValues.length == 1 && splitValues.first == '*') {
      return const IfNoneMatchHeader.wildcard();
    }

    if (splitValues.length > 1 && splitValues.contains('*')) {
      throw FormatException('Wildcard (*) cannot be used with other values');
    }

    final parsedEtags = splitValues.map((value) {
      if (!ETagHeader.isValidETag(value)) {
        throw FormatException('Invalid ETag format');
      }
      return ETagHeader.parse(value);
    }).toList();

    return IfNoneMatchHeader.etags(parsedEtags);
  }

  @override
  String toString() =>
      'IfNoneMatchHeader(etags: $etags, isWildcard: $isWildcard)';
}
