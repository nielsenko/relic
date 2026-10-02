import 'package:relic_core/relic_core.dart';

/// Returns a fresh adapter factory. Called once per server the suite starts.
///
/// [shared] is true when several isolates will each call the returned
/// factory to serve one port.
typedef AdapterFactoryBuilder = Factory<Adapter> Function({bool shared});

/// The adapter under test and the servers the suite starts on it.
final class AdapterConformance {
  final String name;
  final AdapterFactoryBuilder bind;
  final AdapterCapabilities capabilities;

  AdapterConformance(
    this.name, {
    required this.bind,
    required this.capabilities,
  });

  /// Whether WebSocket upgrades can work at all: the adapter either upgrades
  /// itself or exposes a raw channel the core can frame over.
  bool get supportsWebSocket => capabilities.webSocket || capabilities.hijack;

  /// Why WebSocket tests are skipped, or null when they run.
  String? get skipWebSocket =>
      supportsWebSocket ? null : '$name has no WebSocket support';

  /// Why hijack tests are skipped, or null when they run.
  String? get skipHijack =>
      capabilities.hijack ? null : '$name has no hijack support';

  /// A server on port 0 that has not started yet.
  RelicServer create({final int noOfIsolates = 1}) =>
      RelicServer(bind(shared: noOfIsolates > 1), noOfIsolates: noOfIsolates);

  /// A started server serving [handler].
  Future<RelicServer> serve(
    final Handler handler, {
    final int noOfIsolates = 1,
  }) async {
    final server = create(noOfIsolates: noOfIsolates);
    await server.mountAndStart(handler);
    return server;
  }
}

extension ConformanceServerUrl on RelicServer {
  /// The URL a local client reaches this server on.
  ///
  /// A server cannot know what URL it is addressed by before a request
  /// arrives, but for a loopback test the port is enough.
  Uri get url => Uri.http('localhost:$port');
}
