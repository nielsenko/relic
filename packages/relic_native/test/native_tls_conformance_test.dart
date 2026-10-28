import 'dart:io';

import 'package:http/io_client.dart';
import 'package:relic_core/relic_core.dart';
import 'package:relic_native/relic_native.dart';
import 'package:test/test.dart';
import 'package:test_utils/adapter_conformance.dart';

/// The conformance tests of what goes over the wire, over TLS, so the
/// bytes go through tls.zig's records.
void main() {
  final tls = NativeTls.fromFiles(
    certificateChain: 'test/certs/localhost_cert.pem',
    privateKey: 'test/certs/localhost_key.pem',
  );
  final trustTestCa = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates('test/certs/ca_cert.pem');
  final conformance = AdapterConformance(
    'NativeAdapter over TLS',
    bind: ({bool shared = false}) =>
        () => NativeAdapter.bind(InternetAddress.loopbackIPv4, tls: tls),
    capabilities: const AdapterCapabilities(hijack: true, webSocket: true),
    connect: (port) =>
        SecureSocket.connect('localhost', port, context: trustTestCa),
    scheme: 'https',
    newClient: () => IOClient(HttpClient(context: trustTestCa)),
  );

  group('NativeAdapter over TLS.', () {
    framingTests(conformance);
    headerWireTests(conformance);
    requestBodyTests(conformance);
  });
}
