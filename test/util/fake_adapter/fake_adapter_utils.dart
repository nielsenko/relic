/// In-memory adapter utilities for testing without network traffic.
///
/// This library provides [FakeAdapter] and [FakeHttpClient] which work in
/// concert to bypass all network traffic in tests.
library;

export '../test_harness.dart';
export 'fake_adapter.dart';
export 'fake_http_client.dart';
