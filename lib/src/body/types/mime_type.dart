/// A mime type.
class MimeType {
  /// Text mime types.
  static const plainText = MimeType('text', 'plain');

  /// HTML mime type.
  static const html = MimeType('text', 'html');

  /// CSS mime type.
  static const css = MimeType('text', 'css');

  /// CSV mime type.
  static const csv = MimeType('text', 'csv');

  /// JavaScript mime type.
  static const javascript = MimeType('text', 'javascript');

  /// JSON mime type.
  static const json = MimeType('application', 'json');

  /// XML mime type.
  static const xml = MimeType('application', 'xml');

  /// Binary mime type.

  static const octetStream = MimeType('application', 'octet-stream');

  /// PDF mime type.
  static const pdf = MimeType('application', 'pdf');

  /// RTF mime type.
  static const rtf = MimeType('application', 'rtf');

  /// Multipart form data mime type.
  static const multipartFormData = MimeType('multipart', 'form-data');

  /// Multipart byteranges mime type.
  static const multipartByteranges = MimeType('multipart', 'byteranges');

  /// URL-encoded form MIME type.
  static const urlEncoded = MimeType('application', 'x-www-form-urlencoded');

  /// The primary type of the mime type.
  final String primaryType;

  /// The sub type of the mime type.
  final String subType;

  const MimeType(this.primaryType, this.subType);

  /// Parses a mime type from a string.
  /// It splits the string on the '/' character and expects exactly two parts.
  /// First part is the primary type, second is the sub type.
  /// If the string is not a valid mime type then a [FormatException] is thrown.
  factory MimeType.parse(final String type) {
    final parts = type.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid mime type $type');
    }

    final primaryType = parts[0];
    final subType = parts[1];

    if (primaryType.isEmpty || subType.isEmpty) {
      throw FormatException('Invalid mime type $type');
    }

    return MimeType(primaryType, subType);
  }

  /// Returns the value to use for the Content-Type header.
  String toHeaderValue() => '$primaryType/$subType';

  @override
  String toString() => 'MimeType(primaryType: $primaryType, subType: $subType)';
}
