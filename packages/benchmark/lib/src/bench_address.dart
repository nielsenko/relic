import 'dart:io';

/// The address the benchmark servers listen on, BENCH_ADDRESS when it is
/// set and the IPv4 loopback otherwise. A server in a network namespace of
/// its own, reached over a veth pair, needs the address of its end.
final InternetAddress benchAddress = InternetAddress(
  Platform.environment['BENCH_ADDRESS'] ?? InternetAddress.loopbackIPv4.address,
);
