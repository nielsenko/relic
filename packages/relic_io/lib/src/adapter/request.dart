import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:relic_core/relic_core.dart';

import 'request_body.dart';

/// Creates a new [Request] from an [io.HttpRequest], on [exchange], with
/// [create]. Its body reads [body].
///
/// Throws [FormatException] for a target that does not decode. The core
/// answers that with 400 before any handler runs.
Request fromHttpRequest(
  io.HttpRequest request,
  AdapterExchange exchange,
  RequestFactory create,
  IORequestBody? body, {
  void Function()? onBodyEnd,
}) {
  final url = request.requestedUri;
  final target = RequestTarget.fromUri(url)..validate();
  final headers = headersFromHttpRequest(request);
  return create(
    Method.parse(request.method),
    exchange,
    url: url,
    target: target,
    headers: headers,
    body: bodyFromHttpRequest(request, headers, body, onBodyEnd: onBodyEnd),
    lazyConnectionInfo: () =>
        connectionInfoFromHttpConnectionInfo(request.connectionInfo),
  );
}

/// The HTTP version [request] arrived with.
HttpProtocol httpProtocolOf(io.HttpRequest request) =>
    switch (request.protocolVersion) {
      '1.0' => HttpProtocol.http10,
      _ => HttpProtocol.http11,
    };

/// Whether the connection goes on after the response to [request].
///
/// Every Connection option counts, and close wins (RFC 9112 9.3), where
/// dart:io's `persistentConnection` follows the later of the two.
bool keepAliveOf(io.HttpRequest request) {
  final options =
      request.headers[io.HttpHeaders.connectionHeader] ?? const <String>[];
  bool lists(String option) =>
      options.any((value) => value.toLowerCase() == option);
  if (lists('close')) return false;
  return request.protocolVersion != '1.0' || lists('keep-alive');
}

ConnectionInfo connectionInfoFromHttpConnectionInfo(
  io.HttpConnectionInfo? info,
) {
  if (info == null) return ConnectionInfo.empty;
  return ConnectionInfo(
    remote: SocketAddress(
      address: IPAddress.fromBytes(info.remoteAddress.rawAddress),
      port: info.remotePort,
    ),
    localPort: info.localPort,
  );
}

Headers headersFromHttpRequest(io.HttpRequest request) {
  final store = MapHeaderStore();
  request.headers.forEach(
    (name, values) => store.set(HeaderName.lookup(name), values),
  );
  return Headers.fromStore(store);
}

/// The body of [request], typed by [headers], read from [body].
///
/// A request without [body] has none. The body opens lazily: one rejected
/// unread is then never listened to. [onBodyEnd] runs when a chunked body
/// has been read to its end.
Body bodyFromHttpRequest(
  io.HttpRequest request,
  Headers headers,
  IORequestBody? body, {
  void Function()? onBodyEnd,
}) {
  if (body == null) return Body.empty();
  final length = request.contentLength;
  final chunked = length < 0;
  final contentType = headers.tryGet(Headers.contentType);
  return Body(
    open: () => chunked && onBodyEnd != null
        ? body.stream.transform(_endingWith(onBodyEnd))
        : body.stream,
    contentLength: chunked ? null : length,
    bodyType: contentType == null
        ? null
        : BodyType.fromContentType(contentType),
  );
}

StreamTransformer<Uint8List, Uint8List> _endingWith(void Function() onDone) =>
    StreamTransformer.fromHandlers(
      handleDone: (sink) {
        onDone();
        sink.close();
      },
    );

/// Extension to convert a [ContentType] to a [MimeType].
extension ContentTypeExtension on io.ContentType {
  /// Converts a [ContentType] to a [MimeType].
  /// We are calling this method 'toMimeType' to avoid conflict with the 'mimeType' property.
  MimeType get toMimeType => MimeType(primaryType, subType);
}
