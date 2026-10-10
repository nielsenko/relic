part of 'native_adapter.dart';

/// What a message taken with relic_ws_read is. Mirrors `WsKind` in
/// src/relic_native.zig.
enum _WsKind {
  text,
  binary,

  /// The peer's close frame, echoed already: two bytes of code and the
  /// reason, or nothing when it carried no code.
  close,

  /// The peer broke the protocol and was sent a close frame: its code and
  /// reason.
  failed,

  /// The connection ended without a close frame.
  dropped;

  static _WsKind of(final int code) => switch (code) {
    1 => text,
    2 => binary,
    3 => close,
    4 => failed,
    5 => dropped,
    _ => throw StateError('relic_native: unknown message kind $code'),
  };
}

/// A [RelicWebSocket] framed by the native side. The connection's task
/// reads and unmasks the peer's frames, assembles its messages, checks
/// text and close frames, answers pings, and ends the connection on a
/// violation with the close code it calls for. Dart sends and receives
/// whole messages.
///
/// The close handshake: whoever closes first sends a close frame, the
/// native side waits up to two seconds for the other side's, and the
/// connection ends. Pings go out every [pingInterval] when one is set,
/// and a peer that has not answered one before the next is due is gone:
/// the socket closes with 1001.
final class NativeWebSocket extends RelicWebSocketBase {
  final NativeExchange _exchange;

  /// The pongs counted when the last ping went out. The same count when
  /// the next is due means the peer never answered.
  int? _pongsAtPing;

  NativeWebSocket._(this._exchange);

  @override
  void sendFrame(final WebSocketOpcode opcode, final Uint8List payload) =>
      _exchange._wsSend(opcode, payload);

  @override
  void onPing() => _pongsAtPing = _exchange._wsPongs;

  /// The native side counts the pongs, so a ping is answered when the
  /// count moved since it went out.
  @override
  bool pingAnswered() {
    final pongs = _exchange._wsPongs;
    return pongs == null || pongs != _pongsAtPing;
  }

  /// A message from the native side. [bytes] is a view of memory that is
  /// freed when this returns, so what is kept is copied out of it.
  void _onMessage(final _WsKind kind, final Uint8List bytes) {
    switch (kind) {
      case _WsKind.text:
        addEvent(TextDataReceived(utf8.decode(bytes)));
      case _WsKind.binary:
        addEvent(BinaryDataReceived(Uint8List.fromList(bytes)));
      case _WsKind.close:
        markCloseSent();
        final code = bytes.length >= 2 ? (bytes[0] << 8) | bytes[1] : 1005;
        final reason = bytes.length > 2 ? utf8.decode(bytes.sublist(2)) : '';
        closeEvents(CloseReceived(code, reason));
      case _WsKind.failed:
        markCloseSent();
        final code = (bytes[0] << 8) | bytes[1];
        final reason = utf8.decode(bytes.sublist(2));
        addError(WebSocketException(reason));
        closeEvents(CloseReceived(code, reason));
      case _WsKind.dropped:
        closeEvents(CloseReceived(1006, ''));
    }
  }

  /// The connection is gone, however it went.
  void _gone() {
    closeEvents(CloseReceived(1006, ''));
    completeDone();
  }
}
