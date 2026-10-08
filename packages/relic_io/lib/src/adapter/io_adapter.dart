import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:relic_core/relic_core.dart';
import 'package:stream_channel/stream_channel.dart';

import 'bind_http_server.dart';
import 'io_relic_web_socket.dart';
import 'request.dart';
import 'response.dart';

/// An [Adapter] implementation for `dart:io` [HttpServer].
///
/// This adapter bridges Relic with a standard Dart HTTP server, allowing
/// Relic applications to handle HTTP requests and responses, as well as
/// WebSocket connections.
class IOAdapter implements Adapter {
  final io.HttpServer _server;
  StreamSubscription<io.HttpRequest>? _subscription;

  /// Connections that have been detached from [_server].
  ///
  /// Hijacking and upgrading both take the connection out of the underlying
  /// server's bookkeeping, so from that point on nothing else knows they
  /// exist. They are tracked here so shutdown can close the hijacked ones
  /// and [connectionsInfo] can report both kinds.
  final _hijackedSockets = <io.Socket>{};
  final _webSockets = <IORelicWebSocket>{};

  /// How long a graceful shutdown waits for a detached connection to finish
  /// on its own before it is closed anyway.
  ///
  /// Without a ceiling a peer that never answers would keep the shutdown
  /// pending forever.
  static const _drainTimeout = Duration(seconds: 5);

  /// Creates an [IOAdapter] that wraps the provided [io.HttpServer].
  ///
  /// The adapter will listen for incoming requests from the [_server] once
  /// [start] is called.
  IOAdapter(this._server);

  /// Binds an HTTP server to the given [address] and [port].
  ///
  /// If [context] is provided, a secure HTTPS server will be started using
  /// [io.HttpServer.bindSecure]. Otherwise, an HTTP server will be started
  /// using [io.HttpServer.bind].
  ///
  /// - [address]: The [io.InternetAddress] to bind the server to.
  /// - [port]: The port number to listen on. Defaults to 0, which means
  ///   the operating system will assign an available port.
  /// - [context]: An optional [io.SecurityContext] for HTTPS. If null, HTTP is used.
  /// - [backlog]: The maximum length of the queue for incoming connections.
  ///   Defaults to 0 (system-dependent).
  /// - [v6Only]: Whether to only accept IPv6 connections. This is only
  ///   meaningful for IPv6 addresses. Defaults to false.
  /// - [shared]: Whether to allow multiple `HttpServer` objects to bind to the
  ///   same combination of [address], [port] and [v6Only]. Defaults to false.
  ///
  /// Returns a [Future] that completes with the bound [io.HttpServer].
  static Future<IOAdapter> bind(
    final io.InternetAddress address, {
    final int port = 0,
    final io.SecurityContext? context,
    final int backlog = 0,
    final bool v6Only = false,
    final bool shared = false,
  }) async {
    return IOAdapter(
      await bindHttpServer(
        address,
        port: port,
        context: context,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      ),
    );
  }

  /// The [io.InternetAddress] the underlying server is listening on.
  io.InternetAddress get address => _server.address;

  @override
  AdapterCapabilities get capabilities =>
      const AdapterCapabilities(hijack: true, webSocket: true);

  @override
  List<Listener> get listeners => [
    Listener(Transport.tcp, _server.address.address, _server.port, const {
      HttpProtocol.http10,
      HttpProtocol.http11,
    }),
  ];

  @override
  void start(final ExchangeSink sink) {
    if (_subscription != null) throw StateError('start was already called');
    _subscription = _server.listen((final request) {
      final pending = sink(IOExchange._(this, request));
      // The sink never fails by contract. An error here is a bug in the
      // core, and the zone around `start` reports it.
      if (pending is Future<void>) unawaited(pending);
    });
  }

  @override
  Future<void> close({final bool force = false}) async {
    if (force) {
      await _server.close(force: true);
      _destroyDetached();
      return;
    }
    await _server.close();
    await _closeDetached().timeout(_drainTimeout, onTimeout: _destroyDetached);
    _destroyDetached();
  }

  /// Asks every hijacked connection to close. The WebSockets got their
  /// going-away close from the server before this.
  ///
  /// The tracking set is deliberately left alone: a hijacked socket removes
  /// itself when it completes, so whatever is still tracked when the drain
  /// deadline passes is exactly what [_destroyDetached] must drop.
  Future<void> _closeDetached() async {
    await Future.wait([
      for (final socket in _hijackedSockets.toList()) socket.close(),
    ], eagerError: false).catchError((final _) => const <Object?>[]);
  }

  /// Drops whatever is left without waiting for the peer. `dart:io`
  /// exposes no hard teardown for an upgraded socket, and bounds the close
  /// handshake the server started itself.
  void _destroyDetached() {
    for (final socket in _hijackedSockets.toList()) {
      socket.destroy();
    }
    _hijackedSockets.clear();
    _webSockets.clear();
  }

  @override
  ConnectionsInfo get connectionsInfo {
    final info = _server.connectionsInfo();
    final detached =
        _hijackedSockets.length +
        _webSockets.where((final ws) => !ws.isClosed).length;
    return (
      active: info.active + detached,
      closing: info.closing,
      idle: info.idle,
    );
  }

  void _trackHijacked(final io.Socket socket) {
    _hijackedSockets.add(socket);
    unawaited(
      socket.done
          .catchError((final _) {})
          .whenComplete(() => _hijackedSockets.remove(socket)),
    );
  }

  void _trackWebSocket(final IORelicWebSocket webSocket) {
    _webSockets.add(webSocket);
    unawaited(webSocket.done.whenComplete(() => _webSockets.remove(webSocket)));
  }
}

/// One `dart:io` request and its response.
final class IOExchange implements AdapterExchange {
  final IOAdapter _adapter;
  final io.HttpRequest _request;

  /// How the exchange ended, once it has. The completers exist only for a
  /// caller that asked before then.
  ExchangeEnd? _end;
  Completer<ExchangeEnd>? _done;
  Completer<void>? _cancelled;

  IOExchange._(this._adapter, this._request) {
    // dart:io reports a peer that went away as an error on `done`. That is
    // the only signal it gives, and it only fires once something was
    // written, so `cancelled` is best effort on this adapter.
    _request.response.done.then(
      (_) {},
      onError: (final Object _) => _finish(ExchangeEnd.cancelledByPeer),
    );
  }

  @override
  HttpProtocol get protocol => httpProtocolOf(_request);

  @override
  Request toRequest() => fromHttpRequest(_request, this);

  /// A write that fails leaves the exchange open. The core answers with an
  /// error response, and [abort] when that fails too, which is what ends
  /// the exchange.
  @override
  Future<void> respond(final Response response) async {
    await response.writeHttpResponse(
      _request.response,
      method: _framingMethod,
      protocol: httpProtocolOf(_request),
      keepAlive: _request.persistentConnection,
    );
    _finish(ExchangeEnd.completed);
  }

  /// Only HEAD changes how a response is framed, so every other method
  /// frames as GET. That includes one relic has no [Method] for, whose
  /// 400 must still go out.
  Method get _framingMethod =>
      _request.method == Method.head.value ? Method.head : Method.get;

  @override
  Future<StreamChannel<Uint8List>> hijack() async {
    final socket = await _request.response.detachSocket(writeHeaders: false);
    _adapter._trackHijacked(socket);
    _finish(ExchangeEnd.hijacked);
    return StreamChannel<Uint8List>(socket, _SocketSink(socket));
  }

  @override
  Future<RelicWebSocket> upgradeWebSocket() async {
    final webSocket = await IORelicWebSocket.fromHttpRequest(_request);
    _adapter._trackWebSocket(webSocket);
    _finish(ExchangeEnd.upgraded);
    return webSocket;
  }

  @override
  void abort() {
    if (_end != null) return;
    _finish(ExchangeEnd.aborted);
    final response = _request.response;
    try {
      unawaited(
        response
            .detachSocket(writeHeaders: false)
            .then((final socket) => socket.destroy())
            .catchError((final _) {}),
      );
    } on StateError {
      // The head went out, and dart:io detaches no such response. It does
      // destroy the connection of a response that ends in an error, which
      // a body that failed on the socket already did.
      try {
        response.addError(const io.SocketException('aborted'));
      } on StateError {
        // The failed body is still bound to the response.
      }
    }
  }

  @override
  Future<void> get cancelled => _end == ExchangeEnd.cancelledByPeer
      ? Future.value()
      : (_cancelled ??= Completer<void>()).future;

  @override
  Future<ExchangeEnd> get done {
    final end = _end;
    if (end != null) return Future.value(end);
    return (_done ??= Completer<ExchangeEnd>()).future;
  }

  void _finish(final ExchangeEnd end) {
    if (_end != null) return;
    _end = end;
    _done?.complete(end);
    if (end == ExchangeEnd.cancelledByPeer) _cancelled?.complete();
  }
}

/// The socket's sink, narrowed to [Uint8List].
///
/// `StreamChannel.cast` would pipe a controller into the socket instead,
/// which binds the socket sink to a stream, and a later `socket.close()`
/// from shutdown then throws.
final class _SocketSink implements StreamSink<Uint8List> {
  final io.Socket _socket;

  _SocketSink(this._socket);

  @override
  void add(final Uint8List data) => _socket.add(data);

  @override
  void addError(final Object error, [final StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(final Stream<Uint8List> stream) =>
      _socket.addStream(stream);

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;
}
