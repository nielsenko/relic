# relic_native, design

`relic_native` is a second Relic adapter: a Zig HTTP server (zio and
`std.http.Server`) that each Dart isolate drives from its own thread. This
document describes what is built. `NOTES.md` holds the measurements and the
reasoning behind the detours, `PLAN.md` the phases it was built in.

## 1. Goal

Better throughput and better tail latency than the `dart:io` adapter under
production-like load, with the same handlers, middleware and router. The
target is p99 and p999 at 70 to 80% of saturation, not hello-world requests
per second.

Two things came with it and stay:

- `relic_core`'s adapter interface leaves room for h2, h3 and WebTransport
  without changing the request model.
- The header primitives (`HeaderName`, `HeaderStore`) live in `relic_headers`,
  a package with no dependencies, so jaspr and others can use them without
  Relic's typed-header codecs.

## 2. Not in scope

- TLS in process. Terminate it in front.
- HTTP/2, HTTP/3, WebTransport. The interface has the enums and the
  capability flags. No adapter implements them.
- `sendfile` and zero-copy file serving.
- Replacing `relic_io`. It stays the default: `app.serve()` uses it and the
  `relic` package does not depend on `relic_native`. The native adapter is
  opt-in through `package:relic_native` and `serveNative`.

## 3. Decisions

| # | Decision | Why |
|---|----------|-----|
| D1 | One reactor per isolate, a zio runtime on the isolate's own thread, ticked from the adapter's event loop. | No cross-thread hand-off per request, and nothing to lock: sockets belong to tasks, Dart touches exchanges between ticks. The executor rebinds to the calling thread on every tick, since an isolate can run its next event on another OS thread. Per-request CPU is 23.5 us against 32.3 us for the executor-pool design it replaced. |
| D2 | zio plus `std.http.Server` on Zig 0.17.0. | zio implements `std.Io`, so `std.http.Server` runs unmodified and one task per connection keeps the server code plain. `std.Io.Kqueue` was unfinished in 0.16.0 (36 `@panic("TODO")`), when the choice was made. zio comes from the `executor-tick` branch of `nielsenko/zio`, which carries the `Executor.tick` patch, until that is upstream. |
| D3 | One acceptor thread per server hands each socket to the reactor with the fewest connections, scanning from a rotating start. | Routes around an isolate stuck in GC or a slow handler. The kernel backlog never waits on Dart. `SO_REUSEPORT` hashes statically and cannot balance. |
| D4 | One Dart wake per idle-to-busy transition. A waiter thread blocks on the loop's host handle and posts one port message. The isolate drains in batches. | Under load the isolate never goes idle, so the wake cost disappears. A message to the isolate's own port costs 0.7 us where a zero `Timer.run` costs 10.5 us through the dart:io event handler thread. |
| D5 | The request head, its slot table and an inline body are copied into Dart memory when the exchange is dequeued. Headers decode lazily from that copy. | A `Request` is plain Dart data with no lifetime tied to the connection, so post-response logging and stored requests are safe. The copy is about 1 KB per request. |
| D6 | Dart encodes the response head straight into native `malloc` memory. Ownership passes to native, which frees after writing. | One transfer, no copy on the native side. |
| D7 | The adapter calls the core through a synchronous callback returning `FutureOr<void>`. | A sync handler completes in the call with no await. The return value tells the adapter whether the exchange finished synchronously. |
| D8 | Header names are interned (`HeaderName`, small ids for the standard names). Values decode from Latin-1 on first access and are cached per `Headers` instance. Codecs with a byte decoder parse the wire bytes directly. | Removes most per-request `String` allocations. ASCII becomes a `OneByteString` with no widening. |
| D9 | `HeaderName`, `HeaderStore`, `MutableHeaderStore` and `MapHeaderStore` are the `relic_headers` package. `Headers` is a typed accessor view over a `HeaderStore`, shaped like `QueryParameters` and `FormFields`. The `Map` API is gone, with `entries` kept as a deprecated extension. | One accessor pattern across path, query, form and headers. Other packages build headers without Relic's codecs. |
| D10 | `Body` keeps its bytes when built from a `String` or a `Uint8List`. | The in-call response path writes them in one call and never drains a stream. |
| D11 | Isolates join one native server through an explicit group token. | Every test binds port 0 and `noOfIsolates: n` calls the factory n times. Keyed by address, that would be n servers. |
| D12 | WebSocket framing for `relic_native` is Dart code in `relic_core`, over the hijacked byte channel. | `web_socket_channel` 3.x ships no transport-agnostic framer and `dart:io` frames only through its own upgrade. In Dart the framer is shared by every adapter and unit-tested without sockets. |
| D13 | On Windows the waiter thread waits on a futex word with a 10 ms bound instead of a loop handle. | zio's IOCP loop has no handle a host thread can wait on. An idle reactor is ticked every 10 ms until a request wakes it. |

## 4. Architecture

```
 acceptor thread, one per server (zio runtime, one executor)
   accept -> TCP_NODELAY -> pick the reactor with the fewest connections
          -> push the socket on its MPSC queue -> poke its waiter

 isolate thread, one reactor per isolate
   Dart: relic_reactor_tick()  runs the ready tasks, polls the loop once,
                               spawns a task per new socket, returns up to
                               64 ready exchanges
   task: receiveHead -> copy head into scratch -> index header slots
         -> read an inline body, or stream it through the inbound queue
         -> push the Exchange on the ready list -> park on exchange.done
   Dart: copies head, slots and body out -> NativeExchange -> core sink
         -> handler -> respond() encodes the head into native memory
         -> relic_respond() sets exchange.done
   task: writes head and body, or pumps the outbound chunk queue
         -> frees -> loops for keep-alive
   Dart: nothing left -> relic_reactor_wait() arms the waiter thread
   waiter thread: blocks on the loop's host handle (kqueue, epoll or ring
                  descriptor) and a pipe -> one port message -> Dart ticks
```

Sockets are touched only by tasks. Dart touches only exchanges, and only
between ticks, so nothing on the request path takes a lock. The acceptor
thread shares the per-reactor connection count, the incoming queue and the
attach lock.

## 5. Core interface (`relic_core`, `relic_headers`)

### 5.1 Adapter

```dart
typedef ExchangeSink = FutureOr<void> Function(AdapterExchange exchange);

abstract interface class Adapter {
  AdapterCapabilities get capabilities;   // hijack, webSocket, webTransport,
                                          // trailers, lifetimeBoundViews, sendFile
  List<Listener> get listeners;           // transport, host, port, protocols
  void start(ExchangeSink sink);
  Future<void> close({bool force = false});
  ConnectionsInfo get connectionsInfo;    // active, closing, idle
}
```

`relic_io` advertises `hijack` and `webSocket`. `relic_native` advertises
`hijack`. `Adapter.port` remains as a deprecated extension over `listeners`.

### 5.2 AdapterExchange

One request and its response. An h1 request now, an h2 or h3 stream later.

```dart
abstract interface class AdapterExchange {
  HttpProtocol get protocol;              // http10, http11, h2, h3
  Request toRequest();
  FutureOr<void> respond(Response response);
  FutureOr<StreamChannel<Uint8List>> hijack();
  FutureOr<RelicWebSocket> upgradeWebSocket();
  void abort();
  Future<void> get cancelled;             // the peer went away
  Future<ExchangeEnd> get done;           // completed, upgraded, hijacked,
                                          // aborted, cancelledByPeer
}
```

- `toRequest` builds the `Request` from the adapter's own `RequestTarget`,
  `HeaderStore` and `Body`, all lazy. It throws `FormatException` for a
  malformed target or Host, which the core answers with 400.
- Exactly one of `respond`, `hijack`, `upgradeWebSocket` or `abort`, once.
  A `respond` on an exchange the adapter already aborted, or whose peer hung
  up, is a no-op. A second `respond` is a `StateError`.
- `respond` writes what `ResponseFraming.of` decided in the core: the
  Content-Type from the body, the length or the codings, a Date when the
  response has none, no body for a HEAD or a 1xx, 204 or 304, and whether
  the connection closes after. Both adapters frame the same bytes, and the
  conformance suite checks it over raw sockets.
- `upgradeWebSocket` is called only on an adapter with `capabilities.webSocket`.
  Otherwise the core does the RFC 6455 handshake and framing itself over
  `hijack()` (5.9).

### 5.3 Header primitives (`relic_headers`)

No dependencies beyond the SDK. The interface, the names and one reference
store. The typed-header codecs and the decode cache stay in `relic_core`.

```dart
final class HeaderName {
  final int id;        // small stable id for a standard name, -1 otherwise
  final String lower;  // canonical lowercase, the key for == and hashCode
  static HeaderName lookup(String name);           // throws FormatException
  static HeaderName? lookupBytes(Uint8List bytes, int start, int end);
  // about 110 standard names as static consts, generated by
  // tool/generate_header_names.dart from tool/header_names.txt
}

abstract base class HeaderStore {
  // The two abstract members.
  Iterable<HeaderName> get names;
  Iterable<String> values(HeaderName name);
  // Defaults, overridable: fieldCount, value, contains, isEmpty, isNotEmpty,
  // forEach, newMutable, toMutable.
}

abstract base class MutableHeaderStore extends HeaderStore {
  void set(HeaderName name, Iterable<String> values); // empty removes
  void add(HeaderName name, String value);
  void remove(HeaderName name);
  void clear();
  // Every writer rejects CR, LF and NUL.
}

final class MapHeaderStore extends MutableHeaderStore { ... }
```

A base class with two abstract members, not an interface: the package can
grow a method without breaking a store in another package.

`ByteHeaderStore` is in `relic_core`, not published as a stability
commitment: a `Uint8List` head plus an `Int32List` slot table, Latin-1
decode on first read, one `String?` cache per slot. It relies on the
adapter's parser having rejected CR, LF and NUL.

`newMutable()` and `toMutable()` give a caller the store the adapter prefers
for a response without plumbing a factory. Every store returns a
`MapHeaderStore` today. `respond` accepts any `HeaderStore` and encodes it
through `names` and `values`.

### 5.4 Headers (`relic_core`)

```dart
final class Headers extends HeaderStore with AccessorStateMixin, _StoreReads {
  factory Headers.fromStore(HeaderStore store);
  factory Headers.fromMap(Map<String, Iterable<String>>? values);
  factory Headers.empty();
  factory Headers.build(void Function(MutableHeaders) update);
  Headers transform(void Function(MutableHeaders) update);
  T get<T>(accessor);        // throws MissingHeaderException or InvalidHeaderException
  T? call<T>(accessor);      // null when absent, throws when invalid
  T? tryGet<T>(accessor);    // null when absent or invalid
  Iterable<String>? operator [](Object key);   // HeaderName, name text or accessor
  Map<String, List<String>> toMap();
}

final class MutableHeaders extends MutableHeaderStore with AccessorStateMixin, _StoreReads {
  void assign<T>(HeaderAccessor<T> accessor, T? value);   // null removes
  void operator []=(Object key, Iterable<String>? values); // null removes
  // set, add, remove, clear from MutableHeaderStore
}
```

- `Headers` is immutable. The guarantee is in the types: a `MutableHeaders`
  is not a `Headers`, so a live builder cannot be handed to a `Response` and
  mutated afterwards. `Headers.build` and `transform` wrap the builder's
  store and drop the builder.
- Both classes delegate to an inner store and share the read path through
  one private base mixin on `HeaderStore`, so the byte-decode fast path has
  one copy.
- `call` takes the wire bytes from a `ByteHeaderStore` when the codec has
  a byte decoder, else the first value for a single-value codec, else the
  list.
  Decoded values are cached per instance, keyed by accessor and raw value.
  `assign` primes the cache with the value it encoded.
- The named getters and setters (`headers.contentLength`, `mh.date = ...`)
  are hand-written sugar in `standard_headers_extensions.dart`.
- `HeaderAccessor<T>` is a `ReadOnlyAccessor<T, HeaderName, Iterable<String>>`
  with an encode side. `HeaderCodec` is the decode and encode pair, with an
  optional byte decoder.

### 5.5 RequestTarget

Bytes first: `pathBytes` and `queryBytes`. `path`, `pathSegments` and
`queryParametersAll` decode on first read. `pathSegments` splits on `/`
before percent-decoding, as `Uri.pathSegments` does, so an encoded separator
stays inside its segment.

`Request.url` is built on first read from the target, the authority and the
scheme the adapter passes. The core validates the authority when the request
is built: a plain name with at most a numeric port passes a character scan,
and an IP literal, a second colon or a non-numeric port goes through
`Host.parse`. A request without a Host gets the listener's address,
bracketed for IPv6. `Request.connectionInfo` and `Request.cancelled` come
from the exchange the request was built on, the first on first read.

### 5.6 Body

`Body` is the one body type on both sides.

- `bytes` is set by `Body.fromString`, `Body.fromBytes` and `Body.fromData`.
  An adapter writes it in one call.
- `read()` returns the stream once. A second read is a `StateError`. The
  native adapter calls it before anything goes out, so a body that was
  already read ends in a 500 and not a half-written response.
- `readAll({maxLength})` is synchronous when `bytes` is set.
- `contentLength` is null for a stream of unknown length, which goes out
  chunked.
- `Body.ofRequest` types a request body from its Content-Type for both
  adapters, with the bytes an adapter read inline or the stream it hands
  over. A request without a body is `Body.empty()`, so `isEmpty` is true
  for a plain GET. A Content-Type that does not parse counts as none.

### 5.7 Forward compatibility

`HttpProtocol`, `Transport`, the `Listener` list and the capability flags
`webSocket`, `webTransport`, `trailers`, `lifetimeBoundViews` and `sendFile`
exist in the interface. Nothing implements h2, h3, trailers or send-file.
`ConnectionsInfo` keeps its released shape, and a stream count waits for
the h2 work.

### 5.8 Dispatch and errors

`RelicServer` resolves the adapter once and calls `adapter.start(_handle)`.
`_handle` never throws and never returns a failed Future. Its caller is the
adapter, and for `relic_native` that is the drain loop.

`_fail` maps what a handler lets through: `HeaderException` to 400,
`FormException` to its own status, `MaxBodySizeExceeded` to 413, anything
else to a logged 500. If the error response itself fails, for example
because a streamed response already sent its head, it falls back to
`abort()`.

One guarded zone around `start()` catches errors from `unawaited` work. No
per-request zones. No `await` on the sync path.

### 5.9 WebSocket over hijack

`FramedWebSocket` in `relic_core` implements `RelicWebSocket` over a raw
byte channel: RFC 6455 frame decoding with reserved-bit, opcode, mask and
control-frame checks, message assembly with UTF-8 validation, server frames
unmasked, pings on `pingInterval` with 1001 on a missed pong, the close
handshake with a 2 s wait for the peer's close frame and a 2 s bound on the
channel flush. A frame or message over `maxMessageSize` (16 MiB by default)
closes with 1009. `WebSocketUpgrade` refuses a cross-origin upgrade with 403
unless `allowAnyOrigin` is set.

`RelicServer` keeps every WebSocket it hands to a handler, framed here or
upgraded by the adapter, and sends 1001 through `RelicWebSocket.closeGoingAway`
on `close()`, before the adapter drops the connections. The adapters only
track what `connectionsInfo` needs.

## 6. Native side (`relic_native`)

### 6.1 Threads

- `relic_server_bind` starts one acceptor thread per server with its own zio
  runtime. It binds with `reuse_address`, accepts with a 1 s timeout so the
  stop flag is seen, sets `TCP_NODELAY`, and above `maxConnections` sleeps
  1 ms between checks and leaves new connections in the kernel backlog.
- `relic_reactor_create` builds a reactor on the calling thread with a zio
  runtime of one executor, a Vyukov MPSC queue for incoming sockets, a FIFO
  of ready exchanges, an event list and a waiter thread.
- Connection tasks run in a `zio.Group` on the reactor. Task stacks are
  zio's growable reservations, so 10k connections cost address space, not
  RSS.

### 6.2 Per-connection task

1. Wait for the first byte under `idleTimeout`, then `receiveHead` under
   `headerTimeout`. Oversize is 431, a malformed head is 400, a timeout is
   408. Each is written with a 1 s lingering close that drains what the peer
   still sends. These two waits and the write of a response of up to
   64 KiB carry no timer of their own: the connection holds one deadline
   and a sweeper task per reactor cancels the task of a connection past
   it, a quarter of the shortest timeout late at most, and a second at
   most. Body reads, streamed and larger responses keep a timeout on each
   operation.
2. Check the framing `std.http.Server` is lenient on: CRLF line endings, a
   final empty line, a colon in every field line, no folding, a token for
   every field name and no control character but a tab in a value. Copy
   the head into per-connection scratch (16 KiB) and index up to 128
   `HeaderSlot`s against the copy, remembering the Host slot.
3. A body with `Content-Length` up to `maxInlineBody` (1 MiB default) is
   read now under `bodyTimeout`. A chunked or larger body streams to Dart
   through the inbound chunk queue, 64 KiB per chunk, at most 4 chunks ahead
   of what Dart has taken. `Expect` that cannot be met is 417.
4. Build the `Exchange` on the task's stack, push it on the ready list, and
   park on `exchange.done`. When Dart asked for `cancelled`, a peer watcher
   reads the socket meanwhile and posts `peer_gone` on EOF.
5. On `done`: write the head and the body, or pump the outbound chunk
   queue, chunked on the wire when the length is unknown. Free the buffers.
   Loop on keep-alive. A body the handler did not read is drained up to
   4 MiB so the connection can be reused, and the connection closes beyond
   that.

While stopping, a request that arrives gets 503.

### 6.3 Ticks and wakes

- `relic_reactor_tick(wait_ms, out, max)` runs the ready tasks, polls the
  loop once bounded by `wait_ms`, spawns a task per incoming socket and
  returns up to `max` ready exchanges. `relic_reactor_pending` says whether
  to call again at once.
- The Dart drain: up to 4 batches of 64 per event-loop turn with a zero
  wait, then one tick that lingers 1 ms in the kernel, then
  `relic_reactor_wait`. Another turn is scheduled through a message to the
  isolate's own port, never a timer. The Date value comes from the core's
  `httpDate`, which reads the wall clock once per second.
- `relic_reactor_wait` arms the waiter thread with the loop's next timer
  deadline. The waiter polls the loop's host handle and a pipe (a futex
  word with a 10 ms bound on Windows, D13), then posts one
  `Dart_PostInteger_DL`. A stop or an earlier deadline reaches it through
  the pipe. The acceptor pokes it too: `Loop.wake` coalesces on a flag that
  only a real poll clears, so a wake posted to an idle loop can be lost.
- `relic_reactor_events` hands Dart the exchanges with something to say
  since the last tick: a peer gone, a write failure, chunks written, the end
  of a hijacked connection. That last one is posted by a frame about to
  die, so it carries a tag in the low bit of the address and Dart does not
  read the view.

### 6.4 Isolates

- A process-wide registry keyed by a group string. The first
  `NativeAdapter.bind` with a group creates the server and resolves port 0.
  Later binds with the same group join it. Without a group the server is
  private to the caller.
- `serveNative` mints `relic_native/<pid>/<n>` per call and passes it
  through the factory, so `noOfIsolates: n` works with port 0. A direct
  `NativeAdapter.bind` under `RelicApp.run` with several isolates needs an
  explicit `group`.
- A server holds `reactorCapacity` slots (64 by default). The last reactor
  to detach stops the server and joins its thread.
- `connectionsInfo` sums over isolates. The lowest attached reactor reports
  the server-wide counts and the others report zero, so the sum is one
  snapshot.

### 6.5 FFI (C ABI)

```
relic_init_dart_api(data) -> isize                      idempotent
relic_server_bind(group, ip, port, Options*) -> Server*  create or join, null group = private
relic_server_port(Server*) -> u16
relic_server_stats(Server*, Stats*)
relic_reactor_create(Server*, Dart_Port) -> Reactor*     on the calling thread
relic_reactor_destroy(Reactor*)                         blocks while connections unwind
relic_reactor_tick(Reactor*, wait_ms, ExchangeView** out, max) -> u32
relic_reactor_pending(Reactor*) -> bool
relic_reactor_events(Reactor*, usize* out, max) -> u32
relic_reactor_wait(Reactor*)
relic_reactor_slot(Reactor*) -> u32
relic_respond(view, head, head_len, body, body_len, close_after)
relic_respond_stream(view, head, head_len, close_after, chunked)
relic_write_chunk(view, data, len) -> bool              false: data stays Dart's
relic_finish_stream(view, ok)                           ok false drops the connection
relic_read_chunk(view, data*, len*, status*) -> u8      0 when nothing is queued
relic_watch(view)                                       post peer_gone on EOF
relic_hijack(view)                                      raw channel over the chunk queues
relic_abort(view)
relic_alloc(len) -> u8*, relic_free(p)                  Dart's response buffers
```

- The per-exchange calls, `relic_reactor_events`, `relic_reactor_pending`,
  `relic_reactor_slot` and the allocator are leaf calls, which hold off GC
  safepoints for the isolate group and so stay short. `relic_reactor_tick`,
  `relic_reactor_wait`, bind, create and destroy are ordinary calls: a tick
  may linger 1 ms in the kernel and a destroy blocks while connections
  unwind.
- `ExchangeView`, `HeaderSlot`, `Options` and `Stats` are `extern struct`s
  mirrored by Dart `Struct`s. A test compares the sizes.
- Dart never passes Dart-heap pointers to native. Response buffers come from
  `relic_alloc`.
- The Dart DL API sources are vendored under `src/dart-dl/`. `build.zig`
  translates `dart_api_dl.h` with `addTranslateC` and compiles
  `dart_api_dl.c` into the library. Every isolate calls
  `relic_init_dart_api`.

### 6.6 Lifecycle

- Graceful `close()`: wait up to 5 s for in-flight exchanges, close the sinks
  of hijacked connections and wait up to 5 s for the native side to flush
  and let go, abort whatever is left, destroy the reactor. The last reactor
  stops the server. Exchanges that arrive while draining are aborted at
  once.
- Forced `close()`: abort everything, then destroy.
- `RelicServer.close()` sends 1001 on the WebSockets it framed before the
  adapter closes, so the close frame is on the wire before the connection
  drops.
- A peer that hangs up while the exchange is parked completes
  `Request.cancelled`, when the handler asked for it, and the eventual
  `respond` is a no-op.
- Hijack: the handler gets a `StreamChannel<Uint8List>`. An inline body it
  did not read comes first on the stream. Closing the sink closes the
  connection after the flush. The adapter counts hijacked connections
  separately from in-flight exchanges.

### 6.7 Memory ownership

| Memory | Owner | Freed by |
|--------|-------|----------|
| Head copy and slots | task stack | implicit. Dart copies at dequeue |
| Inline request body | reactor allocator | task, after `done`. Dart copies at dequeue |
| Inbound chunks | `malloc` by the task | Dart, with `relic_free`, after copying |
| Response head and body | `relic_alloc` by Dart | task, after writing |
| Outbound chunks | `relic_alloc` by Dart | task, after writing |
| `Exchange` | task stack | implicit |

Dart never touches an `ExchangeView` after `relic_respond`, `relic_abort` or
the last event of a hijacked connection. `NativeExchange` nulls its pointer
and throws on reuse.

### 6.8 Build and packaging

The layout follows `serverpod_argon2`.

- `build.zig` and `build.zig.zon` at the package root. `minimum_zig_version`
  is 0.17.0. zio is pinned to a commit of `nielsenko/zio` by URL and hash.
- `hook/build.dart` uses `binary/<os>-<arch>/` when present (the published
  package), else runs `zig build -Dtarget=... --release=fast -Dstrip=true`.
  The target-to-triple table is `NativeTarget`, shared with
  `tool/build_binaries.dart`. The hook tracks the Zig sources of every path
  dependency, so with zio pointed at a local checkout an edit there
  rebuilds the library.
- The `zig` on `PATH` must report `minimum_zig_version`, or be anyzig, which
  reads that field. CI uses `mlugg/setup-zig@v2`.
- Targets: linux-x64, linux-arm64, macos-arm64, macos-x64, windows-x64,
  windows-arm64. Elsewhere the hook emits no asset and `NativeAdapter.bind`
  throws `UnsupportedError`.
- Windows runs on zio's IOCP backend with the bounded waiter (D13).
- `publish-relic-native.yaml` builds `binary/` on a tag and smoke-tests the
  prebuilt library on each OS with the zig build files removed.
  `native-sanitizers.yaml` runs the Zig tests under ThreadSanitizer nightly
  on Linux. `tool/linux_test.dart` runs them in Docker on io_uring and on
  epoll.
- On Linux the loop runs on io_uring, or on epoll where the kernel refuses
  the ring. zio is built with `io_uring_single_issuer` off: a SINGLE_ISSUER
  ring is entered only by the thread that made it, and the Dart VM moves an
  isolate between the threads of its pool.
- All Relic packages share one version, 2.0.0-rc.2.

### 6.9 Options

`NativeAdapter.bind(address, {port, group, reactorCapacity: 64,
maxInlineBody: 1 MiB, backlog: 128, maxConnections: 0, idleTimeout: 60 s,
headerTimeout: 10 s, bodyTimeout: 30 s, writeTimeout: 30 s})`. A zero
duration disables that limit. `serveNative` exposes the same, minus the
group and the inline limit. A head is at most 16 KiB with at most 128
fields.

## 7. Tests

Given/When/Then names throughout.

- The adapter conformance suite in `test_utils` runs against `relic_io` and
  `relic_native`: serving, response framing over raw sockets, request
  bodies, server lifecycle, connection counts, shutdown, response failures,
  hijack, WebSocket and WebSocket origin checks. This is the main
  correctness net.
- `relic_native` tests on top: head framing, the four timeouts and the
  connection cap, streamed bodies both ways, peer cancellation, graceful
  close with a hijacked connection, Host handling, bodyless statuses, the
  struct layouts and the response encoder. They run on every OS.
- `relic_core` tests for the dispatch invariants through a fake adapter, the
  framer against hand-built frames, the header stores and the accessor
  cache.
- Zig unit tests: the MPSC queue under contention, the registry and attach
  limits, a tick driven by a libc client, and `checkRequestBytes` over a
  request corpus with a seeded mutation sweep. The `std.testing.fuzz` entry
  is there for a test runner that builds it. The tick test is skipped on
  Windows.
- `tool/soak.dart` runs mixed traffic for a set time and samples RSS and
  open descriptors.

## 8. Benchmarks

`packages/benchmark` holds, besides the router micro-benchmarks:

- `http_load.dart`: each adapter through a `RelicApp`, driven by oha. A
  closed-loop run finds the saturation rate, then open-loop runs at
  fractions of it report the latency percentiles. Workloads: plaintext,
  JSON, browser-like headers, an allocating route, and a mixed-latency
  route.
- `hello_sweep.dart`: the hello route over isolate counts with the server's
  CPU sampled mid-run.
- `cpu_bench.dart` with `hello_serve.dart`: CPU time per request from the
  kernel's per-process counters, for any server command.
- `cpu_profile.dart`: VM CPU samples by tag and function for a running
  server.
- `ws_echo.dart`: WebSocket echo round trips, which compares the Dart
  framer over hijack with `dart:io`'s.

The numbers are in `NOTES.md`.

## 9. Risks and open items

| Item | State |
|------|-------|
| zio is pinned to a fork with the `Executor.tick` patch | Upstream it, then pin a release. |
| `std.http.Server` is not a hardened internet-facing parser | Own framing checks before it, own limits and timeouts around it, fuzz corpus in the suite. Replacing it with `std.http.HeadParser` and own framing is the fallback. |
| Windows idle tick | 10 ms (D13). Runtime behaviour is covered by CI only. Revisit if zio exposes a waitable handle. |
| Drain fairness against the Dart event loop | Batch size, batches per turn and the linger are constants. Measure timer latency under load before making them options. |
| The Dart framer is new code on the WebSocket path | Frame-level unit tests, the conformance suite and the echo benchmark. The Autobahn suite has not been run. |
| Least-loaded dispatch uses an approximate connection count | Fine for routing. Revisit if skew shows in benchmarks. |
| `maxMessageSize` for WebSockets is not exposed on `WebSocketUpgrade` | A handler cannot raise the 16 MiB limit yet. |
