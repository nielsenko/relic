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
final class NativeWebSocket implements RelicWebSocket {
  final NativeExchange _exchange;
  final _events = StreamController<WebSocketEvent>();
  final _done = Completer<void>();
  Timer? _pingTimer;
  Duration? _pingInterval;

  /// The pongs counted when the last ping went out. The same count when
  /// the next is due means the peer never answered.
  int? _pongsAtPing;
  var _closeSent = false;

  NativeWebSocket._(this._exchange);

  @override
  Future<void> get done => _done.future;

  @override
  Stream<WebSocketEvent> get events => _events.stream;

  @override
  bool get isClosed => _events.isClosed;

  @override
  String get protocol => '';

  @override
  Duration? get pingInterval => _pingInterval;

  @override
  set pingInterval(final Duration? value) {
    _pingInterval = value;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongsAtPing = null;
    if (value == null || _closeSent) return;
    _pingTimer = Timer.periodic(value, (_) {
      final pongs = _exchange._wsPongs;
      if (pongs == null) return;
      if (pongs == _pongsAtPing) {
        _goAway(1001, '');
        return;
      }
      _pongsAtPing = pongs;
      _exchange._wsSend(WebSocketOpcode.ping, Uint8List(0));
    });
  }

  @override
  void sendBytes(final Uint8List b) {
    if (!trySendBytes(b)) throw WebSocketConnectionClosed();
  }

  @override
  void sendText(final String s) {
    if (!trySendText(s)) throw WebSocketConnectionClosed();
  }

  @override
  bool trySendBytes(final Uint8List b) {
    if (isClosed) return false;
    _exchange._wsSend(WebSocketOpcode.binary, b);
    return true;
  }

  @override
  bool trySendText(final String s) {
    if (isClosed) return false;
    _exchange._wsSend(WebSocketOpcode.text, utf8.encode(s));
    return true;
  }

  @override
  Future<void> close([final int? code, final String? reason]) async {
    if (!await tryClose(code, reason)) throw WebSocketConnectionClosed();
  }

  @override
  Future<bool> tryClose([final int? code, final String? reason]) async {
    if (isClosed) return false;
    checkCloseCode(code);
    checkCloseReason(reason);
    _closeEvents();
    _sendClose(code, reason ?? '');
    return true;
  }

  @override
  Future<void> closeGoingAway() {
    if (!isClosed) {
      _closeEvents();
      _sendClose(1001, 'Server shutting down');
    }
    return _done.future;
  }

  /// Closes from this side with [code], and the handler sees that close.
  void _goAway(final int code, final String reason) {
    _closeEvents(CloseReceived(code, reason));
    _sendClose(code, reason);
  }

  void _sendClose(final int? code, final String reason) {
    if (_closeSent) return;
    _closeSent = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _exchange._wsSend(WebSocketOpcode.close, encodeClosePayload(code, reason));
  }

  /// Ends the handler's events, after [close] when it should hear how the
  /// connection closed. Nothing happens on events that already ended.
  void _closeEvents([final CloseReceived? close]) {
    if (_events.isClosed) return;
    if (close != null) _events.add(close);
    unawaited(_events.close());
  }

  /// A message from the native side. [bytes] is a view of memory that is
  /// freed when this returns, so what is kept is copied out of it.
  void _onMessage(final _WsKind kind, final Uint8List bytes) {
    switch (kind) {
      case _WsKind.text:
        if (!_events.isClosed) {
          _events.add(TextDataReceived(utf8.decode(bytes)));
        }
      case _WsKind.binary:
        if (!_events.isClosed) {
          _events.add(BinaryDataReceived(Uint8List.fromList(bytes)));
        }
      case _WsKind.close:
        _closeSent = true;
        _pingTimer?.cancel();
        final code = bytes.length >= 2 ? (bytes[0] << 8) | bytes[1] : 1005;
        final reason = bytes.length > 2 ? utf8.decode(bytes.sublist(2)) : '';
        _closeEvents(CloseReceived(code, reason));
      case _WsKind.failed:
        _closeSent = true;
        _pingTimer?.cancel();
        final code = (bytes[0] << 8) | bytes[1];
        final reason = utf8.decode(bytes.sublist(2));
        if (!_events.isClosed) _events.addError(WebSocketException(reason));
        _closeEvents(CloseReceived(code, reason));
      case _WsKind.dropped:
        _closeEvents(CloseReceived(1006, ''));
    }
  }

  /// The connection is gone, however it went.
  void _gone() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _closeEvents(CloseReceived(1006, ''));
    if (!_done.isCompleted) _done.complete();
  }
}
