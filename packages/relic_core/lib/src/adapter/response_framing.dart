import 'package:relic_headers/relic_headers.dart';

import '../body/types/body_type.dart';
import '../body/types/mime_type.dart';
import '../context/result.dart';
import '../headers/exception/header_exception.dart';
import '../headers/standard_headers_extensions.dart';
import '../headers/typed/headers/transfer_encoding_header.dart';
import '../router/method.dart';
import '../util/http_date.dart';
import '../util/util.dart';
import 'adapter.dart';

/// What goes on the wire for a [Response], decided once so every adapter
/// frames the same bytes for the same response.
///
/// An adapter writes the response's headers except [HeaderName.contentLength],
/// [HeaderName.contentType] and [HeaderName.transferEncoding], then what
/// is here: the body decides the length and the type, the server the date.
final class ResponseFraming {
  /// Whether body bytes follow the head. Not for a HEAD request, and not
  /// for a 1xx, 204 or 304.
  final bool sendBody;

  /// The Content-Length to announce, or null.
  final int? contentLength;

  /// The Transfer-Encoding codings to announce, or null. `chunked` is last
  /// when [chunked].
  final List<String>? transferEncoding;

  /// Whether the body goes out in chunked coding.
  final bool chunked;

  /// The Content-Type from the body, or null for a body without one.
  final String? contentType;

  /// The Date to add, or null when the response has one.
  final String? date;

  /// Whether the connection closes after this response: the request or
  /// the response asked for it, or the end of the body is the only way
  /// the peer learns where the body ends.
  final bool closeAfter;

  const ResponseFraming._({
    required this.sendBody,
    required this.contentLength,
    required this.transferEncoding,
    required this.chunked,
    required this.contentType,
    required this.date,
    required this.closeAfter,
  });

  /// The framing of [response] to a request made with [method] over
  /// [protocol], on a connection the request keeps alive or not.
  ///
  /// Throws [FormatException] when the body's type does not validate, or
  /// a header of the response that the framing reads does not parse, so a
  /// response that cannot be written fails before anything went out.
  factory ResponseFraming.of(
    final Response response, {
    required final Method method,
    required final HttpProtocol protocol,
    required final bool keepAlive,
  }) {
    final headers = response.headers;
    final body = response.body;
    final hasBody = statusMayHaveBody(response.statusCode);

    final bodyType = body.bodyType;
    String? contentType;
    if (bodyType != null) {
      bodyType.validate();
      contentType = bodyType.toHeaderValue();
    }
    final date = headers.contains(HeaderName.date) ? null : httpDate();
    // Most responses set neither Connection nor Transfer-Encoding, and
    // then nothing is parsed and no list is built for them.
    final connection = headers.contains(HeaderName.connection)
        ? _own(() => headers.connection, HeaderName.connection)
        : null;
    var closeAfter = !keepAlive || (connection?.isClose ?? false);

    int? contentLength;
    List<String>? transferEncoding;
    var chunked = false;
    if (hasBody) {
      // The codings a handler set stay, except chunked, which is decided
      // here from the body's length.
      List<String>? codings;
      if (headers.contains(HeaderName.transferEncoding)) {
        codings = [
          for (final coding
              in _own(
                    () => headers.transferEncoding,
                    HeaderName.transferEncoding,
                  )?.encodings ??
                  const <TransferEncoding>[])
            if (coding.name != TransferEncoding.chunked.name) coding.name,
        ];
        if (codings.isEmpty) codings = null;
      }
      final length = body.contentLength;
      if (length != null && codings == null) {
        // A message with Transfer-Encoding has no Content-Length (RFC 9112
        // 6.1), so a coded body is framed by its coding even when its
        // length is known.
        contentLength = length;
      } else if (protocol == HttpProtocol.http10 ||
          (codings?.contains(TransferEncoding.identity.name) ?? false) ||
          _isMultipartByteranges(bodyType)) {
        // Nothing frames the body, so the connection's end does.
        closeAfter = true;
      } else {
        chunked = true;
        (codings ??= []).add(TransferEncoding.chunked.name);
      }
      transferEncoding = codings;
    }
    return ResponseFraming._(
      sendBody: hasBody && method != Method.head,
      contentLength: contentLength,
      transferEncoding: transferEncoding,
      chunked: chunked,
      contentType: contentType,
      date: date,
      closeAfter: closeAfter,
    );
  }

  /// A header of the response, read as typed. One the handler set with a
  /// value that does not parse is the handler's error, not the client's,
  /// so it is a [FormatException] and not the [HeaderException] the core
  /// answers with 400.
  static T _own<T>(final T Function() read, final HeaderName name) {
    try {
      return read();
    } on HeaderException catch (e) {
      throw FormatException(
        "The response's ${e.headerType} header does not parse: "
        '${e.description}',
      );
    }
  }

  /// Whether [name] is written from the framing, not from the headers.
  static bool isFramingHeader(final HeaderName name) =>
      name == HeaderName.contentLength ||
      name == HeaderName.contentType ||
      name == HeaderName.transferEncoding;

  /// A multipart/byteranges body frames itself with Content-Range
  /// (RFC 7233 4.1), so it is not chunked.
  static bool _isMultipartByteranges(final BodyType? type) =>
      type != null &&
      type.mimeType.primaryType == MimeType.multipartByteranges.primaryType &&
      type.mimeType.subType == MimeType.multipartByteranges.subType;
}
