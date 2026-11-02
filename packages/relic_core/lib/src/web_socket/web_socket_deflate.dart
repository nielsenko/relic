import 'package:relic_headers/relic_headers.dart';

import '../context/result.dart';

/// How a server offers permessage-deflate (RFC 7692) on an upgrade.
///
/// The client offers the extension, and the server accepts it within these
/// bounds or leaves it out. Compression costs CPU on every message and up
/// to a few hundred kilobytes of memory per connection, so it is off until
/// an upgrade asks for it.
final class WebSocketCompression {
  /// The extension with its defaults: full context takeover both ways, a
  /// 32 KB window each, and messages under [threshold] bytes sent as is.
  static const defaults = WebSocketCompression();

  /// The largest LZ77 window the server compresses with, as a power of two
  /// from 9 to 15. Smaller is less memory per connection and a worse ratio.
  final int serverMaxWindowBits;

  /// The largest window the client may compress with, as a power of two
  /// from 8 to 15. The client decides within it.
  final int clientMaxWindowBits;

  /// Whether the server starts every message from an empty window, which
  /// frees its compressor between messages.
  final bool serverNoContextTakeover;

  /// Whether to ask the client to start every message from an empty window.
  final bool clientNoContextTakeover;

  /// The deflate level, 1 for fastest to 9 for smallest.
  final int level;

  /// Messages under this many bytes go out uncompressed. Deflate rarely
  /// shrinks a short message, and every compressed one costs a flush.
  final int threshold;

  const WebSocketCompression({
    this.serverMaxWindowBits = 15,
    this.clientMaxWindowBits = 15,
    this.serverNoContextTakeover = false,
    this.clientNoContextTakeover = false,
    this.level = 6,
    this.threshold = 64,
  }) : assert(serverMaxWindowBits >= 9 && serverMaxWindowBits <= 15),
       assert(clientMaxWindowBits >= 8 && clientMaxWindowBits <= 15),
       assert(level >= 1 && level <= 9),
       assert(threshold >= 0);
}

/// The permessage-deflate parameters a handshake agreed on. The adapter's
/// framer compresses and decompresses with these.
final class WebSocketDeflate {
  final int serverMaxWindowBits;
  final int clientMaxWindowBits;
  final bool serverNoContextTakeover;
  final bool clientNoContextTakeover;
  final int level;
  final int threshold;

  const WebSocketDeflate({
    required this.serverMaxWindowBits,
    required this.clientMaxWindowBits,
    required this.serverNoContextTakeover,
    required this.clientNoContextTakeover,
    required this.level,
    required this.threshold,
  });

  /// The `Sec-WebSocket-Extensions` value that accepts the offer with these
  /// parameters (RFC 7692 7.1).
  ///
  /// A window of 15 bits is the default, and the client's is only named
  /// when it offered to take one, so neither is written then.
  String get headerValue {
    final buffer = StringBuffer('permessage-deflate');
    if (serverNoContextTakeover) buffer.write('; server_no_context_takeover');
    if (clientNoContextTakeover) buffer.write('; client_no_context_takeover');
    if (serverMaxWindowBits < 15) {
      buffer.write('; server_max_window_bits=$serverMaxWindowBits');
    }
    if (clientMaxWindowBits < 15) {
      buffer.write('; client_max_window_bits=$clientMaxWindowBits');
    }
    return buffer.toString();
  }
}

/// The parameters to accept the first permessage-deflate offer in
/// [request] that fits [compression], or null to leave the extension out.
///
/// An offer the server cannot honour, such as a window smaller than it
/// compresses with, is skipped for the next (RFC 7692 7.1.2). A malformed
/// offer, with a parameter named twice or a value out of range, is skipped
/// too.
WebSocketDeflate? negotiateWebSocketDeflate(
  Request request,
  WebSocketCompression compression,
) {
  for (final field in request.headers.values(
    HeaderName.secWebsocketExtensions,
  )) {
    for (final offer in field.split(',')) {
      final accepted = _accept(offer, compression);
      if (accepted != null) return accepted;
    }
  }
  return null;
}

WebSocketDeflate? _accept(String offer, WebSocketCompression compression) {
  final parts = offer.split(';').map((p) => p.trim()).toList();
  if (parts.first.toLowerCase() != 'permessage-deflate') return null;
  var serverBits = compression.serverMaxWindowBits;
  var clientBits = compression.clientMaxWindowBits;
  var serverNoTakeover = compression.serverNoContextTakeover;
  var clientNoTakeover = compression.clientNoContextTakeover;
  // The client may lower the window the server compresses with, or say it
  // takes a window bound at all. Without `client_max_window_bits` in the
  // offer it compresses with 15 bits and accepts no bound.
  var clientBoundOffered = false;
  final seen = <String>{};
  for (final part in parts.skip(1)) {
    if (part.isEmpty) return null;
    final eq = part.indexOf('=');
    final name = (eq < 0 ? part : part.substring(0, eq)).trim().toLowerCase();
    final value = eq < 0 ? null : _unquote(part.substring(eq + 1).trim());
    if (!seen.add(name)) return null;
    switch (name) {
      case 'server_no_context_takeover':
        if (value != null) return null;
        serverNoTakeover = true;
      case 'client_no_context_takeover':
        if (value != null) return null;
        clientNoTakeover = true;
      case 'server_max_window_bits':
        final bits = _windowBits(value);
        if (bits == null || bits < 9) return null;
        if (bits < serverBits) serverBits = bits;
      case 'client_max_window_bits':
        clientBoundOffered = true;
        if (value == null) continue;
        final bits = _windowBits(value);
        if (bits == null) return null;
        if (bits < clientBits) clientBits = bits;
      default:
        return null;
    }
  }
  if (!clientBoundOffered && clientBits < 15) return null;
  return WebSocketDeflate(
    serverMaxWindowBits: serverBits,
    clientMaxWindowBits: clientBits,
    serverNoContextTakeover: serverNoTakeover,
    clientNoContextTakeover: clientNoTakeover,
    level: compression.level,
    threshold: compression.threshold,
  );
}

/// A window size from 8 to 15, or null for anything else.
int? _windowBits(String? value) {
  if (value == null) return null;
  final bits = int.tryParse(value);
  if (bits == null || bits < 8 || bits > 15) return null;
  return bits;
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;
