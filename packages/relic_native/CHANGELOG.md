## 2.0.0-rc.2
- Initial release: `NativeAdapter`, `NativeExchange` and `serveNative` on a
  zio and `std.http.Server` backend, HTTP/1.0 and HTTP/1.1, keep-alive and
  multiple isolates on Linux, macOS and Windows
- Streamed request and response bodies, chunked or with a length, with
  `maxInlineBody` as the limit for a body read before the handler runs
- `idleTimeout`, `headerTimeout`, `bodyTimeout`, `writeTimeout` and
  `maxConnections`, and `Request.cancelled` on a peer that hangs up
- A head that is not CRLF framed, has a field line without a colon, a
  folded line, a field name that is not a token or a control character
  other than a tab in a value is answered 400
- `hijack` hands the connection over as a raw byte channel, and WebSocket
  upgrades run on it with relic_core's framer
- The reactor runs on the isolate's own thread. `bind` and `serveNative`
  take no `executors`, and `queueCapacity` is `reactorCapacity`
- A request builds one `Uri` from its target and validates that, and a
  request without a body does not parse its Content-Type
- The response head is sized and written straight into the buffer the
  native side takes over, and the `Date` value is refreshed once per
  second from a stopwatch
- Closing a server pokes its acceptor awake instead of waiting out the
  accept timeout, so a close returns in milliseconds, not 100 ms
- A status the server answers on its own, 400, 408, 417, 431 or 503, ends
  with a lingering close: the send side is shut, then the peer's remaining
  bytes are dropped for up to a second, so the peer reads the status
  instead of a reset
- The drain schedules itself with a message to the isolate's own port, not
  a zero timer through the event handler thread
- The `Date` value is refreshed once per drain batch, not per response
- The native parser records the Host header's slot, so the request URL's
  authority is read without a scan of the header names
- A request hands over its target bytes and authority, and its URL is
  parsed only when a handler reads it. A Host value outside the authority
  alphabet is answered 400
- The head indexer fills the header slots in its own line scan instead of
  std.http's header iterator
- Accepted sockets get `TCP_NODELAY`, so a streamed response's small
  writes are not held for a delayed ACK
- `zig build baseline` builds `tool/hello_zio.zig`, a hello server on zio
  alone, for measuring what the adapter costs on top of it
- The Dart DL header is translated by a build step and imported as a
  module, in place of `@cImport`, which Zig removed after 0.16
