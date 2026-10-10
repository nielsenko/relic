import 'dart:convert';
import 'dart:io';

import 'package:relic_core/relic_core.dart';
import 'package:relic_native/relic_native.dart';

/// A started server on the loopback with [handler] mounted, with whichever
/// adapter options a test sets.
Future<RelicServer> serveNative(
  final Handler handler, {
  final InternetAddress? address,
  final int maxInlineBody = 1 << 20,
  final int maxConnections = 0,
  final Duration idleTimeout = const Duration(seconds: 60),
  final Duration headerTimeout = const Duration(seconds: 10),
  final Duration bodyTimeout = const Duration(seconds: 30),
  final Duration writeTimeout = const Duration(seconds: 30),
  final int maxWebSocketMessage = FramedWebSocket.defaultMaxMessageSize,
}) async {
  final server = RelicServer(
    () => NativeAdapter.bind(
      address ?? InternetAddress.loopbackIPv4,
      maxInlineBody: maxInlineBody,
      maxConnections: maxConnections,
      idleTimeout: idleTimeout,
      headerTimeout: headerTimeout,
      bodyTimeout: bodyTimeout,
      writeTimeout: writeTimeout,
      maxWebSocketMessage: maxWebSocketMessage,
    ),
  );
  await server.mountAndStart(handler);
  return server;
}

/// Writes [request] on a fresh connection to [server] and returns what it
/// answers until it closes the connection, within five seconds.
Future<String> rawExchange(
  final RelicServer server,
  final String request, {
  final InternetAddress? address,
}) async {
  final socket = await Socket.connect(
    address ?? InternetAddress.loopbackIPv4,
    server.port,
  );
  socket.write(request);
  await socket.flush();
  final reply = await utf8
      .decodeStream(socket)
      .timeout(const Duration(seconds: 5));
  socket.destroy();
  return reply;
}
