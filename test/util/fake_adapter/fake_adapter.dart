import 'dart:async';
import 'dart:typed_data';

import 'package:relic/relic.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket/web_socket.dart';

/// An in-memory [Adapter] implementation for testing without network traffic.
///
/// This adapter processes requests directly in memory, enabling fast,
/// deterministic tests that don't require actual network I/O.
///
/// Use [FakeAdapter] together with [FakeHttpClient] to create a complete
/// testing setup that bypasses all network traffic.
///
/// Example:
/// ```dart
/// final adapter = FakeAdapter();
/// final server = RelicServer(() => adapter);
/// await server.mountAndStart(myHandler);
///
/// final client = FakeHttpClient(adapter);
/// final response = await client.get(Uri.parse('http://localhost/test'));
/// ```
class FakeAdapter extends Adapter {
  final StreamController<AdapterRequest> _requestController =
      StreamController<AdapterRequest>.broadcast();

  final Map<FakeAdapterRequest, Completer<void>> _pendingRequests = {};

  int _activeConnections = 0;
  final int _closingConnections = 0;
  final int _idleConnections = 0;

  bool _isClosed = false;

  @override
  int get port => 0;

  @override
  Stream<AdapterRequest> get requests => _requestController.stream;

  /// Injects a request into the adapter and waits for the response.
  ///
  /// This is called by [FakeHttpClient] to simulate an HTTP request.
  /// Returns a [Future] that completes when the response is available.
  Future<FakeResponse> handleRequest(final FakeAdapterRequest request) async {
    if (_isClosed) {
      throw StateError('Adapter is closed');
    }

    final completer = Completer<void>();
    _pendingRequests[request] = completer;
    _activeConnections++;

    _requestController.add(request);

    await completer.future;
    _activeConnections--;

    return request.response!;
  }

  @override
  Future<void> respond(
    covariant final FakeAdapterRequest request,
    final Response response,
  ) async {
    // Read the body to a list of bytes
    final bodyBytes = await response.body.read().toList();
    final flattenedBytes = bodyBytes.expand((final chunk) => chunk).toList();

    request.response = FakeResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: flattenedBytes,
    );

    final completer = _pendingRequests.remove(request);
    completer?.complete();
  }

  @override
  Future<void> hijack(
    covariant final FakeAdapterRequest request,
    final HijackCallback callback,
  ) async {
    final clientToServer = StreamController<List<int>>();
    final serverToClient = StreamController<List<int>>();

    // Create a channel for the server side (what the callback sees)
    final serverChannel = StreamChannel<List<int>>(
      clientToServer.stream,
      serverToClient.sink,
    );

    // Create a channel for the client side (what the test sees)
    request.hijackedChannel = StreamChannel<List<int>>(
      serverToClient.stream,
      clientToServer.sink,
    );

    request.isHijacked = true;

    // Invoke the callback with the server channel
    callback(serverChannel);

    final completer = _pendingRequests.remove(request);
    completer?.complete();
  }

  @override
  Future<void> connect(
    covariant final FakeAdapterRequest request,
    final WebSocketCallback callback,
  ) async {
    final webSocket = FakeRelicWebSocket();
    request.webSocket = webSocket;

    callback(webSocket);

    final completer = _pendingRequests.remove(request);
    completer?.complete();
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    await _requestController.close();
  }

  @override
  ConnectionsInfo get connectionsInfo => (
    active: _activeConnections,
    closing: _closingConnections,
    idle: _idleConnections,
  );
}

/// A fake adapter request that holds the response once it's ready.
class FakeAdapterRequest extends AdapterRequest {
  final Request _request;

  /// The response set by [FakeAdapter.respond].
  FakeResponse? response;

  /// For hijacked connections, this channel can be used to communicate
  /// with the server.
  StreamChannel<List<int>>? hijackedChannel;

  /// Whether this request was hijacked.
  bool isHijacked = false;

  /// For WebSocket upgrades, this is the fake WebSocket instance.
  FakeRelicWebSocket? webSocket;

  FakeAdapterRequest(this._request);

  @override
  Request toRequest() => _request;
}

/// A simple response container for fake adapter responses.
class FakeResponse {
  final int statusCode;
  final Headers headers;
  final List<int> bodyBytes;

  FakeResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  String get bodyString => String.fromCharCodes(bodyBytes);
}

/// A fake WebSocket implementation for testing.
class FakeRelicWebSocket implements RelicWebSocket {
  final StreamController<WebSocketEvent> _eventsController =
      StreamController<WebSocketEvent>.broadcast();

  final List<Object> _sentMessages = [];

  bool _isClosed = false;
  int? _closeCode;
  String? _closeReason;

  @override
  Duration? pingInterval;

  @override
  String get protocol => '';

  @override
  bool get isClosed => _isClosed;

  @override
  Stream<WebSocketEvent> get events => _eventsController.stream;

  /// Messages sent from the server to the client.
  List<Object> get sentMessages => List.unmodifiable(_sentMessages);

  /// Simulate receiving a text message from the client.
  void receiveText(final String text) {
    _eventsController.add(TextDataReceived(text));
  }

  /// Simulate receiving binary data from the client.
  void receiveBytes(final Uint8List bytes) {
    _eventsController.add(BinaryDataReceived(bytes));
  }

  /// Simulate the client closing the connection.
  void receiveClose([final int? code, final String? reason]) {
    _eventsController.add(CloseReceived(code, reason ?? ''));
  }

  @override
  void sendText(final String s) {
    if (_isClosed) {
      throw StateError('WebSocket is closed');
    }
    _sentMessages.add(s);
  }

  @override
  void sendBytes(final Uint8List b) {
    if (_isClosed) {
      throw StateError('WebSocket is closed');
    }
    _sentMessages.add(b);
  }

  @override
  bool trySendText(final String s) {
    if (_isClosed) return false;
    _sentMessages.add(s);
    return true;
  }

  @override
  bool trySendBytes(final Uint8List b) {
    if (_isClosed) return false;
    _sentMessages.add(b);
    return true;
  }

  @override
  Future<void> close([final int? code, final String? reason]) async {
    _isClosed = true;
    _closeCode = code;
    _closeReason = reason;
    await _eventsController.close();
  }

  @override
  Future<bool> tryClose([final int? code, final String? reason]) async {
    if (_isClosed) return false;
    await close(code, reason);
    return true;
  }

  /// The close code if the WebSocket was closed.
  int? get closeCode => _closeCode;

  /// The close reason if the WebSocket was closed.
  String? get closeReason => _closeReason;
}
