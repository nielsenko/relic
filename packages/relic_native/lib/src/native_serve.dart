import 'dart:io';

import 'package:relic_core/relic_core.dart';

import 'native_adapter.dart';

var _serveCount = 0;

extension RelicAppNativeServeEx on RelicApp {
  /// Starts a native server that listens on [address] and [port] and sends
  /// requests to this app.
  ///
  /// [noOfIsolates] isolates handle requests. They share one native server,
  /// bound once. The group that ties them
  /// together is minted here, so two calls never share a server, and port
  /// 0 works with several isolates.
  ///
  /// If not specified [address] defaults to [InternetAddress.loopbackIPv4]
  /// and [port] to 8080.
  /// The timeouts and [maxConnections] are those of [NativeAdapter.bind].
  Future<RelicServer> serveNative({
    final InternetAddress? address,
    final int port = 8080,
    final int noOfIsolates = 1,
    final int backlog = 128,
    final int maxConnections = 0,
    final Duration idleTimeout = const Duration(seconds: 60),
    final Duration headerTimeout = const Duration(seconds: 10),
    final Duration bodyTimeout = const Duration(seconds: 30),
    final Duration writeTimeout = const Duration(seconds: 30),
  }) {
    final group = 'relic_native/$pid/${_serveCount++}';
    return run(
      () => NativeAdapter.bind(
        address ?? InternetAddress.loopbackIPv4,
        port: port,
        group: group,
        backlog: backlog,
        maxConnections: maxConnections,
        idleTimeout: idleTimeout,
        headerTimeout: headerTimeout,
        bodyTimeout: bodyTimeout,
        writeTimeout: writeTimeout,
      ),
      noOfIsolates: noOfIsolates,
    );
  }
}
