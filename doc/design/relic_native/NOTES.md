# Implementation notes

One entry per phase: what changed, measurements, deviations from
`DESIGN.md`.

## P0, spikes and go/no-go (2026-10-01)

Verdict: go, with one design change (an executor pool instead of a single
I/O thread, D1) and one dispatch fix (rotate ties, 6.3).

Code: a throwaway spike, not kept in the repo (Zig library, vendored
Dart DL API, Dart boundary server, dart:io baseline, benchmark runner).

### P0.1 The sketch against Zig 0.16.0 and zio v0.18.0

Compiled after these corrections to the `std.http` names guessed in the
sketch:

- `receiveHead` and `head_buffer` exist as guessed. `iterateHeaders` too.
- `readerExpectNone` asserts `expect == null`, so a request with
  `Expect: 100-continue` must go through `readerExpectContinue`, which
  writes the interim response. The spike uses `readerExpectContinue`
  everywhere.
- `Request.Head` carries `method`, `target`, `version`, `content_length`,
  `transfer_encoding`, `keep_alive`, `expect` and `content_type`.
- `error.HttpConnectionClosing` is the clean-EOF error. `HttpHeadersOversize`
  is the 431 case, `HttpHeadersInvalid` the 400 case.
- The parser state must be back in `.ready` before the next `receiveHead`
  on a keep-alive connection. `Request.respond` does that through the
  private `discardBody`. A server that writes its own bytes has to do it
  itself: reading a content-length body to the end gets there, and a
  request without a body is reset by hand. `http.Reader.state` is public.
- `Server.init` takes `*std.Io.Reader` and `*std.Io.Writer`. zio's
  `Stream.reader(&buf).interface` and `Stream.writer(&buf).interface`
  plug straight in, as zio's own `examples/http_server.zig` shows.

zio corrections:

- `std.Thread.ResetEvent` is gone in Zig 0.16. `zio.os.ResetEvent` does the
  job for signalling the bound port back to the starting thread.
- `RuntimeOptions.executors = .exact(n)` takes a `u8`.
- `Timeout.fromMilliseconds` exists. `accept(.{ .timeout = ... })` returns
  `error.Timeout`, which the accept loop uses to poll the stop flag.
- `Group.cancel()` waits for every task. A fiber parked shielded on
  `done` never finishes, so stop must come after Dart has answered every
  exchange (6.6 already says so).

### P0.2 Foreign-thread wake

`zig build test` runs two tests. One spawns a fiber that pushes a fresh
stack-allocated `Exchange` through the MPSC queue and waits on its `Event`,
one million times, with an OS thread as the consumer setting each event.
The other pushes a million nodes from four OS threads and pops them from a
fifth. Both pass, the first in about three seconds, so a foreign-thread
`Event.set` on a stack-allocated event is sound and cheap.

### P0.3 to P0.5 Measurements

Machine: MacBookPro16,1, Intel i9-9980HK, 8 cores, macOS 26. Load
generator oha 1.12.1 on the same machine, 64 connections, keep-alive, 10 s
runs, open loop at 50% and 75% of each server's own closed-loop saturation
with `--latency-correction`. Numbers are one run each, so treat them as
indicative. `dart run bin/bench.dart` reproduces a table.

Single isolate, single executor:

| server | saturation rps | load | rps | p50 ms | p99 ms | p999 ms |
|---|---|---|---|---|---|---|
| ceiling (native canned) | 116386 | 50% | 58175 | 0.62 | 1.51 | 13.92 |
| ceiling (native canned) | 116386 | 75% | 87276 | 0.90 | 4.37 | 13.81 |
| boundary (native + dart) | 62291 | 50% | 31137 | 1.04 | 2.18 | 2.72 |
| boundary (native + dart) | 62291 | 75% | 45295 | 1.51 | see below | |
| dart:io | 18935 | 50% | 9467 | 0.57 | 1.41 | 3.07 |
| dart:io | 18935 | 75% | 14199 | 0.88 | 2.33 | 3.28 |

Four isolates, four executors:

| server | saturation rps | load | rps | p50 ms | p99 ms | p999 ms |
|---|---|---|---|---|---|---|
| ceiling (native canned) | 138616 | 50% | 69290 | 0.59 | 2.18 | 20.76 |
| ceiling (native canned) | 138616 | 75% | 103941 | 0.83 | 1.89 | 4.31 |
| boundary (native + dart) | 85647 | 50% | 42813 | 0.64 | 1.53 | 1.89 |
| boundary (native + dart) | 85647 | 75% | 64226 | 0.77 | 1.74 | 2.17 |
| dart:io | 45688 | 50% | 22839 | 0.51 | 1.37 | 1.84 |
| dart:io | 45688 | 75% | 34260 | 0.74 | 1.89 | 2.29 |

Go criteria:

- Boundary throughput at least 1.5x dart:io: 3.3x single isolate, 1.87x
  with four isolates. Pass.
- p99 at 75% load no worse than dart:io's: 1.74 ms against 1.89 ms with
  four isolates. Pass. Single isolate the two are within noise of each
  other (2.3 to 2.6 ms) at three times the request rate.

Findings behind the numbers:

- One native I/O thread caps the boundary at about 63k rps regardless of
  isolate count (four isolates on one executor: 63k). A sample of that
  thread under load: 28% in `sendto`, 28% in `recvfrom`, 12% in `kevent`,
  12% posting wakes to Dart (`Dart_PostInteger` ends in
  `pthread_cond_signal`), the rest parsing and scheduling. It is
  syscall-bound. Four zio executors lift the boundary to 86k. The canned
  ceiling moves less (116k to 139k), since it has no park and wake per
  request. Design change: D1 becomes an executor pool.
- Least-loaded dispatch picks queue 0 on ties, and depths are almost
  always zero, so the main isolate took 71% of requests with four
  isolates. Rotate the starting index on ties (6.3).
- Wakes per request stay high with a trivial handler: about one wake per
  1.5 to 2 requests. Batching only pays once handlers take longer than the
  wake, which real handlers do.
- Every run on this machine can hit one whole-process stall of 300 to
  500 ms, seen with the canned native server (309 ms), the Dart boundary
  (335 ms) and dart:io (510 ms) alike. The native round-trip timers
  (`relic_server_stats`) saw a maximum of 27 ms inside the Dart round trip
  during a stalled run, so the stall is outside the design: kernel, oha,
  or the machine. With latency correction one stall lands on every
  request scheduled during it, which is 5% of a 45k rps run, and that is
  what a 335 ms p99 in a single run means. Repeat runs and read the
  median. P6 must run on a pinned Linux box.
- Thread hopping (P0.5): each isolate's drain loop ran on two different OS
  threads over a run. Nothing in the design depends on thread identity,
  and nothing broke.
- Zig tests and the release build take about ten seconds each. Startup
  with prebuilt binaries is instant.

### Deviations from DESIGN.md

- D1: an executor pool with `executors` configurable, default to be
  chosen in P3 by benchmark (four looked right here). Fibers may migrate
  between executors with zio's default work stealing. The exchange lives
  on the coroutine stack and that stack does not move, so pointers Dart
  holds stay valid.
- 6.3: dispatch rotates its starting queue on equal depths.
- 6.5: `relic_server_start` gained an `executors` argument in the spike.
  The P3 API takes it through `opts`.
- 6.5: the DL API sources were vendored from Dart 3.13.4 (DL version 2.6).
  `Dart_InitializeApiDL` refuses only on a major mismatch, and the
  symbols used (`Dart_PostInteger_DL`) exist since DL 2.0, so the same
  headers work on Dart 3.10. Vendor from 3.10 in P3 anyway so nothing
  newer can creep in.

## P1, core adapter interface refactor (2026-10-01)

Done. Commits: the interface change, the dispatch error-channel tests,
the conformance suite extraction, the dispatch benchmark.

What changed against the plan:

- `AdapterExchange.hijack()` and `upgradeWebSocket()` return `FutureOr`,
  since `dart:io` detaches the socket asynchronously. A native adapter can
  still answer synchronously.
- `AdapterExchange.toRequest()` stays eager in this phase, as planned. The
  lazy request side (`target`, `headers`, `body` on the exchange) is P2.
- `StreamChannel.cast` cannot narrow the hijacked socket to `Uint8List`:
  it pipes a controller into the socket, which binds the sink, and the
  shutdown `socket.close()` then throws "StreamSink is bound to a stream".
  relic_io wraps the socket in its own `StreamSink<Uint8List>` instead.
- `_wrapHandlerWithMiddleware` is gone. Its mapping lives in `_fail`, and
  the `Date` header is set by `IOExchange.respond` on the `dart:io`
  response, not by copying relic `Headers`.
- `cancelled` on `IOExchange` is best effort: `dart:io` only reports a
  peer that went away as an error on `response.done`, after a write.
- The conformance suite runs from relic_io, since that is where the
  adapter lives. relic keeps the TLS tests. The pure `ConnectionInfo`
  value tests moved to relic_core.
- The multi-isolate conformance tests bind with `shared: true`. The
  originals bound port 0 without `shared`, which gave every isolate its
  own port and sent all traffic to the first one.

Measurements, same machine as P0:

| benchmark | before P1 | after P1 |
|---|---|---|
| dispatch, sync handler, in-process, per request | 3.95 us | 0.56 us |
| dispatch, async handler, in-process, per request | 3.89 us | 3.31 us |
| hello over dart:io, oha closed loop, 64 connections, best of 3 | 10551 rps | 11185 rps |

The sync number is the one D7 is about: seven times less work per
request when nothing awaits. The in-process benchmarks are
`Dispatch;Sync` and `Dispatch;Async` in `packages/benchmark`, which CI
records in git notes. The before numbers came from a throwaway script
against the pre-P1 commit in a second jj workspace.

## P2, header primitives and lazy request model (2026-10-01)

Done. Commits: relic_headers, ByteHeaderStore, the Headers rebase, byte
decoding for int headers, RequestTarget with Body.bytes, the header
benchmarks.

What was built:

- `relic_headers` holds `HeaderName` (112 generated names, `lookup`,
  `lookupBytes`), the `HeaderStore` and `MutableHeaderStore` base classes
  with `newMutable` and `toMutable`, and `MapHeaderStore`. No
  dependencies. The generator is `tool/generate_header_names.dart`, and
  the list in `tool/header_names.txt` is append only because the line is
  the id.
- `ByteHeaderStore` in relic_core: bytes plus an `Int32List` slot table,
  names interned on first use, values decoded per field on first read, one
  raw view per field so a cache can key on it.
- `Headers` is a `HeaderStore` view with `get`, `call` and `tryGet` from
  the shared `AccessorStateMixin`, `[]` by name, and `toMap()`.
  `MutableHeaders` is a `MutableHeaderStore` with `assign`. The named
  getters and setters stay. `HeaderAccessor` is a `ReadOnlyAccessor` keyed
  by `HeaderName`; custom accessors use `HeaderName.custom('x-name')`.
- `HeaderCodec.single` takes an optional `decodeBytes`. It may return null
  to decline, and the text decoder stays the reference. `parseIntBytes`
  is wired on the int codecs, so `Content-Length` on a byte store never
  becomes a `String`.
- `RequestTarget` (bytes or Uri backed, decoded on first use, segments
  split before decoding) and `Request.target`. The `Request` constructor
  no longer decodes the path and query. The dart:io adapter validates the
  target and the core answers a failure with 400, which the conformance
  suite checks.
- `Body.bytes` and `Body.readAll`. The dart:io adapter writes a buffered
  body with one `add`.

Deviations from DESIGN.md and PLAN.md:

- `AdapterExchange.respond` still takes a `Response`, and the exchange
  still hands over a `Request` through `toRequest()`. `Body.bytes` gives
  the in-call fast path that `ResponseBody`'s `BytesBody` was for, and
  `Body.readAll` is `BodySource.readAll`. A second body type family bought
  nothing that `Body` could not carry, and the request side stays
  adapter-specific because the dart:io adapter reads Content-Type
  leniently through `dart:io` and the core's typed parser does not. P3
  builds the native request from `ByteHeaderStore`, `RequestTarget` and
  `Body.fromData` directly.
- Byte decoders for `content-type` and `host` are not written. Both need
  the full grammar over bytes, and the win is a Latin-1 copy per header.
  Follow-up after P3, if the profile shows them.
- The decoded-value cache moved from a process-global `Expando` to a
  per-`Headers` cache, as planned, and `transform` carries the cache into
  the headers it builds. That keeps a value assigned through an accessor
  identical on read, which the static file tests depend on: a
  `DateTime` with microseconds survives a round trip through
  `lastModified` in process, although the header only carries seconds.
- `Headers.xHeader` constants stay `String`s. Tests use them as map keys
  and const maps cannot key on `HeaderName`. The accessors are keyed by
  `HeaderName` regardless.
- `MutableHeaders.remove` accepts a name as text or an accessor as well as
  a `HeaderName`, since tests and users remove by text.
- The extension getters are declared twice, on `HeaderValues` and again
  on `MutableHeaders`: Dart picks an extension by member name, so a
  setter-only extension on `MutableHeaders` would hide the getters.
- The parameterized header tests shrank from six checks to four per
  accessor (338 fewer tests), since `isSet`, `isValid`, `valueOrNull` and
  friends collapsed into `contains`, `call`, `tryGet` and `get`.

Measurements, `packages/benchmark`, per request:

| benchmark | ByteHeaderStore | MapHeaderStore |
|---|---|---|
| 18 headers, read host, content-length and cookie | 9.1 us | 15.5 us |
| 18 headers, read every field | 9.1 us | 7.7 us |
| dispatch, sync handler, in-process | 0.04 us | |
| dispatch, async handler, in-process | 1.9 us | |

The map store number includes building the store from eighteen text
fields, which is what the dart:io adapter pays. The byte store number
includes only the wrapper, since the bytes come from the parser. Reading
three headers on the byte store allocates the three value strings, the
three decoded values and one single-element list per read. Nothing is
allocated for the other fifteen fields. Reading every field costs the
byte store fifteen extra decodes and the interning of each name, which is
the 1.4 us it loses on that pattern.

The sync dispatch number fell from 0.56 us in P1 to 0.04 us because the
`Request` constructor stopped decoding the path and query.

## P3, relic_native MVP (2026-10-01)

Done. The package `packages/relic_native` passes the adapter conformance
suite on macOS with the hijack and WebSocket groups skipped by
capability: 62 passed, 28 skipped.

What was built:

- `src/relic_native.zig`: the P0 spike restructured. A group registry
  (`relic_server_bind` creates or joins by group token), dynamic
  `relic_server_attach` and `relic_server_detach` with the last detach
  stopping the server, least-loaded dispatch that rotates its start index
  on ties, peer address and ports in the exchange view, active and idle
  connection counters, and 400, 411, 413, 417, 431 and 503 answered
  natively. Five Zig tests: the MPSC queue, the foreign-thread wake, the
  registry with port 0, separate groups, and a full server.
- `lib/src/bindings.dart`: `@Native` bindings on the bundled asset with
  leaf calls for poll, respond, abort and alloc, and a layout test on the
  struct sizes.
- `NativeAdapter` and `NativeExchange`: attach at bind, drain on wake
  with batches of 64 and a yield every four batches, the request built
  from `ByteHeaderStore`, `RequestTarget.fromBytes` and `Body.fromBytes`,
  the response head encoded once in Dart with a per-second `Date`, and
  graceful close that drops new exchanges at once and aborts what is left
  after five seconds.
- `serveNative` on `RelicApp`, minting one group per call.
- The package follows serverpod_argon2: prebuilt `binary/` for the
  published package, `zig build` from source with an exact version or
  anyzig, no asset and no error on an unsupported target, DL API sources
  vendored from Dart 3.10.0.

Deviations from DESIGN.md and PLAN.md:

- Connection counts. Every isolate of a group shares one server, and
  `RelicServer` sums what each isolate reports. The lowest attached
  isolate reports the server-wide counts and the others report zero, so
  the sum is one snapshot. `Stats.first_attached` carries the index.
- A request without a body is handed over as a body of unknown length,
  empty on read, as the dart:io adapter does. `Body.empty()` would report
  a length of zero, and the conformance suite pins the dart:io behaviour.
- A streamed response body without a buffer is collected with `readAll`
  and sent with a `Content-Length`. Chunked responses come with P4, as
  planned, and a streamed request body is refused with 411.
- A response that fails to encode (a `Content-Type` that does not
  validate, for one) leaves the exchange open, so the 500 the core sends
  next goes out on it. The first version took the exchange before
  encoding and left the connection hanging.
- `Body.fromBytes` was added to relic_core: `Body.fromData` infers a
  media type from magic bytes when none is given, which a request body
  must not do.
- The conformance suite's connection count test held requests for 100 ms
  and waited 100 ms before counting. The native path answered some in
  time for the client to close them. The handler now holds for 500 ms.
- `serverDetach` blocks the calling isolate thread until the native
  thread has joined, on the last detach. That is at most the accept
  poll interval plus the cancellation of idle connections.

Measurements, same machine as P0, oha closed loop, 64 connections, a
`RelicApp` with one route answering `Hello`:

| server | rps | p50 ms | p99 ms |
|---|---|---|---|
| relic_native, 1 isolate, 1 executor | 56522 | 1.03 | 2.37 |
| relic_native, 4 isolates, 4 executors | 102744 | 0.58 | 1.37 |
| P0 boundary, 1 isolate, 1 executor (no Relic) | 62291 | | |
| P0 boundary, 4 isolates, 4 executors (no Relic) | 85647 | | |
| relic on dart:io, 1 isolate (P1 measurement) | 11185 | 5.53 | 8.00 |

The full pipeline sits within 10% of the P0 boundary on one isolate,
which meets the P3 acceptance of 20%. With four isolates it beats the P0
boundary, whose Dart side was a first draft.

## P4, production hardening (2026-10-01)

Done. `packages/relic_native` runs the conformance suite plus its own
limits, cancel, streaming and framing tests: 85 passed, 28 skipped by
capability. The Zig suite is seven tests, two of them the fuzz entries.

What was built, one commit per step:

- Timeouts and a connection cap. `idleTimeout` for the first byte of a
  request, `headerTimeout` for the rest of the head, `bodyTimeout` as
  body inactivity, `writeTimeout` as write inactivity, and
  `maxConnections` as an accept gate. A slow head or body gets 408.
- Peer disconnect while a handler runs. `relic_watch` asks the fiber to
  watch the socket for EOF while parked, and `Request.cancelled`
  completes on the wake. Only a handler that reads `cancelled` pays.
- Streaming bodies both ways. A chunked request body, or one over
  `maxInlineBody`, goes through an inbound chunk queue with `in_credit`
  chunks of read-ahead. A response body without bytes goes through an
  outbound queue with a window of eight chunks, chunked on the wire when
  it has no length. A body the handler never read is drained up to
  `max_discard` bytes so the connection can be reused.
- Fuzzing. `checkRequestBytes` runs a connection's bytes through
  `receiveHead`, `indexHead` and the body reader with no socket. The
  corpus alone, on the first run, found two crashes reachable from the
  network:
  - `GET / HTTP/1.1\n\n`. The std.http head parser accepts a bare LF as
    a terminator, and its header iterator then unwraps a search for
    CRLF.
  - `GET / HTTP/1.1\r\nA:1\r\nB: 2\r\nC:  3  \r\nD\r\n\r\n`. The head
    parser's vector path ends the head after `D\r\n`, two bytes early,
    when the buffer ends exactly there. With more bytes behind it the
    same input parses right. Same iterator crash.
  `indexHead` now refuses a head that does not end in CRLF CRLF, a bare
  LF anywhere, a field line without a colon and a folded line, with 400.
  Zig 0.16.0's test runner does not compile in fuzz mode
  (`test_runner.zig:566`, a `StackTrace` pointer type mismatch), so the
  suite carries a seeded 20K mutation sweep over the corpus, and
  `zig build test --fuzz` is there for a toolchain that builds. A 400K
  sweep ran clean once the framing check was in.
- A declared body on any method. `std.http.Server.readerExpectContinue`
  hands back an empty reader for GET and DELETE, which left the body
  bytes in the stream as the next head. `openBody` opens the body reader
  for the declared framing whatever the method.
- Sanitizer. `zig build test -Dsanitize-thread` builds the Zig tests
  under TSan. A nightly workflow runs it on Linux: 7/7 pass, no reports.
  TSan traps at startup on macOS with Zig 0.16.0, before any test code,
  and the Dart-driven suite cannot run under TSan since the runtime must
  be in the process from the start.
- Error paths. A peer reset while a streamed body is written cancels the
  source and the next request is served. The same with a buffered body.
  A body cut short by the peer fails the handler's read.

The evening's pass over the Dart side, one commit each, ordered by
effort and then by share of a 200 us CPU profile of one isolate under
oha. One isolate, 128 connections, user and system time from
`proc_pid_rusage`:

| step | us per request | rps |
|---|---|---|
| start of the pass | 26.1 | 39619 |
| ContextProperty on a slot list, not an Expando | 16.5 | 61924 |
| routeWith and respondWith pass a sync Response through | 15.6 | 64771 |
| one Uri per request, no RequestTarget in the adapter | 15.3 | 63696 |
| ResponseHead written into the native buffer, Date on a Stopwatch | 13.4 | 76148 |
| zio: a timed wait's race members finish in place | see below | |

The Expando was the surprise: two context property writes per request
were 15 percent of the isolate's samples, and most of the 12 percent
tagged as runtime type checks went with them. GC was 0.1 percent of the
samples on this route, so allocation is not a lever here. The zio
change could not be measured on a quiet box: in the one pair taken
while the hyper control held steady, relic_native sat at 15.0 to 15.4
us against hyper's 13.2 in the same minute, a ratio of 1.15 where the
morning's ratio was 1.3. A quiet rerun replaces this line.

The profile also explained three things that were not throughput:

- The conformance suite took 45 s on this adapter and 22 s on dart:io.
  Every close waited out the acceptor's 100 ms accept poll. The stop
  now pokes the acceptor with a connect through loopback, and the suite
  takes 25 s, the extra 2 s being the ping test dart:io skips.
- The header timeout drip test failed now and then with a connection
  reset. The server wrote the 408 and closed while the client was still
  dripping, and a close with unread input is a reset on macOS, which
  discards the 408 from the client's buffer. Every status-and-close is
  now a lingering close: send side shut, the peer's bytes dropped for up
  to a second.
- The ping test took 2 s because FramedWebSocket waited out its 2 s
  close handshake after a missed pong. It closes the channel at once
  now, as dart:io does.

A second pass took the rest of the list, except the copy of the head
out of native memory, which stays until a view has a lifetime story.
One commit each: the drain schedules itself with a message to the
isolate's own port, the app builds its routing pipeline once per mount,
a byte-backed Body makes its stream only when read, one BodyType per
MIME type and encoding pair, the Date refreshed once per drain batch,
the Host header's slot recorded by the parser, and the request URL
built on first read with routing on the target's segments. Measured
between two hyper control runs in the same minute:

| server | rps | user us | sys us | total us |
|---|---|---|---|---|
| hyper 1.7, 1 thread | 90459 | 4.2 | 6.8 | 11.0 |
| relic_native, 1 isolate | 82849 | 5.5 | 6.6 | 12.1 |

The profile puts Dart at 17 percent of the isolate now, from 28 before
the pass and 38 at the start of the day. The raw port had one subtlety:
its handler runs in whatever zone is current when the message lands,
so the adapter binds it to the zone that started the server, as the
stream port and the zero timer did by themselves.

The tools that produced these numbers live in the repo now:
`packages/benchmark/bin/hello_serve.dart`, `cpu_bench.dart` and
`cpu_profile.dart`, and `packages/relic_native/tool/linux_test.dart`
with its Dockerfile for the Linux runs on both backends. The hyper,
Deno, Go and Node servers are not Dart or Zig and were not kept.

Where the native side's time goes, from `sample` on the isolate thread
with a symbolized library, self time by library: kernel 60 percent
(sendto 34, recvfrom 25), Dart's JIT code 21, librelic_native 13,
malloc 2, the VM 1.5. Inside the 13 percent: zio's park and resume
machinery about 7 (yield, the executor's thread-local lookup, submit,
markCompleted, the timer per timed wait), std.http's header iterator
2.8 (a two-byte sequence search over the head), the line scan and
HeadParser 1, copies 1, clock reads 0.8. Every recv and send runs at
submit, never from the poll, so the sample cannot tell an EAGAIN recv
from a real one, and relic's system time matches hyper's anyway. The
header iterator is gone: indexHead fills the slots from the line scan
it already makes, worth 0.2 to 0.3 us. What is left in zio is spread
over a dozen frames under one percent each, the thread-local executor
lookup and the per-wait timer being the two largest at about a tenth
of a microsecond each.

AOT does not help. `dart build cli` of the hello server measured in
the same conditions:

| server | rps | user us | sys us | total us |
|---|---|---|---|---|
| hyper 1.7, 1 thread | 106529 | 3.5 | 5.8 | 9.4 |
| relic_native, 1 isolate, JIT | 89971 | 5.1 | 6.1 | 11.2 |
| relic_native, 1 isolate, AOT | 68496 | 7.9 | 6.2 | 14.1 |

The JIT's speculative inlining on this hot path is worth 2.7 us of
user time over the AOT code. After the header scan change, one isolate
measured 10.8 and 11.6 us against hyper's 11.0 in the same minute.

Against uWebSockets, the C++ library Bun serves on, and with a hello
server on zio alone (`zig build baseline`) as the control, same minute,
`sample` on the busiest thread converted to microseconds per request:

| server | rps | sendto | recvfrom | kernel | user |
|---|---|---|---|---|---|
| zio alone, 1 executor | 139458 | 3.02 | 2.92 | 6.23 | 0.94 |
| uWebSockets, 1 thread | 136423 | 3.14 | 2.75 | 6.32 | 1.01 |
| relic_native, 1 isolate | 79498 | 4.22 | 3.35 | 7.63 | 4.94 |

By rusage, zio alone and uWebSockets both measure 6.8 us per request,
1.6 user and 5.2 system. zio is at uWebSockets' level, and there was no
microsecond to find in it. relic's extra over that baseline is the Dart
process: 4 us of user time (Dart's own 2.6, the handoff and parse in
Zig 1.1 over zio's 0.9, malloc 0.3, the VM 0.3) and 1.4 us of kernel
time that the same two syscalls cost more inside the VM process, with
no extra syscall to show for it. The would-block recv was counted at
582 of 395 thousand attempts, zio's registration is one EV_CLEAR per
socket, the fault rate under load was lowest for relic, and TCP_NODELAY
moved nothing. The per-call cost rises with the process's own memory
traffic across all four servers, which fits the kernel's socket paths
losing cache lines to the Dart heap between calls, and that is as far
as a sampler can take it. hyper shows the same effect in proportion.

http.zig at its 2026-08-26 head, which takes a std.Io for its handler
side but runs its own kqueue worker for the sockets, same bench, same
minute:

| server | rps | server cpu | user us | sys us | total us |
|---|---|---|---|---|---|
| http.zig, 1 worker, 32 pool threads | 159686 | 224% | 2.8 | 11.3 | 14.0 |
| http.zig, 1 worker, 1 pool thread | 158220 | 180% | 2.3 | 9.1 | 11.4 |
| zio alone, 1 executor | 146292 | 100% | 1.6 | 5.2 | 6.8 |
| uWebSockets, 1 thread | 150274 | 100% | 1.5 | 5.1 | 6.6 |

More requests per second from two threads, at 1.7 to 2 times the CPU
per request, 9 to 11 us of it in the kernel: the worker thread hands
each request to a pool thread and takes the response back, which is
the two-thread shape P7 took out of relic. Not a candidate.

std.http's share of the native side was one thing: std.mem.findPos
falls back to findPosLinear for a needle of two to four elements, and
that compares the whole needle at every position, so every CRLF search
in Request.Head.parse's splitSequence and in HeaderIterator walked the
head byte by byte with a function call per byte. Measured through
std's own code with Zig 0.16.0, nanoseconds per head:

| | small head | browser head |
|---|---|---|
| Head.parse, std | 284 | 4553 |
| Head.parse, findPos with a first-byte scan | 206 | 1153 |
| HeaderIterator, std | 144 | 1162 |
| HeaderIterator, findPos with a first-byte scan | 160 | 815 |

With a master compiler from anyzig (`zig master`, 0.17.0-dev.2384)
through master's own lib, pristine against the workspace, two rounds:

| | small head | browser head |
|---|---|---|
| Head.parse, master | 210 to 238 | 2079 to 2684 |
| Head.parse, patched | 86 to 89 | 332 to 341 |
| HeaderIterator, master | 62 to 63 | 602 to 629 |
| HeaderIterator, patched | 45 to 47 | 207 to 216 |

std's own tests pass with the patch under master: 97 in mem, 91 in
http, run with `zig master test --zig-lib-dir lib lib/std/std.zig
--test-filter <name>` in the workspace.

The fix is in std.mem.findPos: below the Boyer-Moore-Horspool threshold
the first element is found with the vectorized findScalarPos and the
rest compared in place, with a test against findPosLinear over every
short needle of a small alphabet at every start index. HeaderIterator
switches its three findPosLinear calls to findPos. Two commits on the
`findpos-short-needle` bookmark in the jj workspace at
~/Projects/zig/zig-findpos, on master, for Kasper to upstream. relic
builds against the 0.16.0 release and gains the Head.parse part, about
a quarter of a microsecond per request, when a release carries it;
indexHead no longer uses the iterator.

The zio bookmark holds two commits now. The tick commit gained the
Linux wrapper's `hostHandle` and `hasPendingChanges`, without which
nothing compiled on Linux, and a poll that runs the backend when it has
queued registrations: on io_uring a zero-wait tick never flushed the
waker entry, so the host saw pending work forever. The second commit is
the race change. Both suites were run in an ubuntu:24.04 container on
epoll and on io_uring with seccomp unconfined: zio 707 of 708 on each,
the one failure being a DNS lookup with no network, relic_native 8 of 8
with io_uring and with epoll. The Dart suite was not run on Linux.

Deviations from PLAN.md:

- Request chunks are an MPSC queue per exchange with a credit counter,
  not an SPSC ring. The queue type was already there and the consumer
  side is the same code as the exchange queue.
- The soak ran three minutes with mixed traffic, not 24 hours. See below.

Soak, `tool/soak.dart`, same machine as P0, 32 in-process dart:io
clients, two executors, one isolate, mixed traffic (small and 1 MiB
buffered responses, a 1 MiB chunked response, streamed uploads read and
unread, and a connection dropped mid-response), three minutes:

| elapsed s | rss MB | fds | requests | errors |
|---|---|---|---|---|
| 10 | 454 | 165 | 10784 | 0 |
| 60 | 767 | 157 | 69064 | 0 |
| 120 | 1030 | 157 | 129923 | 0 |
| 180 | 1424 | 167 | 193331 | 0 |

File descriptors are flat. The RSS is not, and a run per route put the
growth on the routes that answer with 1 MiB bodies: `big` and `drop` at
about 2.4 MB/s, `chunked` at 3.8 MB/s, `small`, `echo` and `unread`
flat, and the dart:io adapter flat on the same `big` route. Two `vmmap`
snapshots fifty seconds apart on the `big` route explain it: the Dart
heap (`VM_ALLOCATE`) is flat at 205 MB and the dirty pages of
`MALLOC_MEDIUM` are flat at 8 MB, while its resident but clean pages
grow from 132 MB to 228 MB. macOS malloc marks a freed medium block
`MADV_FREE_REUSABLE`, and the RSS counts such pages until the kernel
takes them back under pressure. The physical footprint, sampled every
twenty seconds over a 110 s `big` run, stays between 240 MB and 275 MB
while the RSS passes 760 MB. The tool reports the footprint on macOS
for that reason. No leak, and the 24 h run stays on the list for a
Linux box, where the RSS is the number to read.

## P5, hijack and WebSocket (2026-10-01)

Done. The conformance suite is fully green on both adapters: 115 cases
on relic_native with nothing skipped, 87 on relic_io.

What was built:

- Native hijack. `relic_hijack` turns the parked exchange into a raw
  channel: a reader fiber pushes what the socket has into the inbound
  chunk queue, `in_credit` chunks ahead of Dart, and a writer fiber
  writes the outbound queue as Dart fills it. The connection fiber waits
  for Dart to close its sink (`relic_finish_stream`, which flushes first)
  or abort, cancels both, and posts one last event so Dart drops its
  reference before the frame dies. `NativeExchange.hijack` returns a
  `StreamChannel<Uint8List>` over that, with an unread inline request
  body first, which is what the dart:io adapter's detached socket does.
- WebSocket in relic_core (D12). `WebSocketFrameDecoder` checks what a
  server checks at the frame level (reserved bits, opcodes, the mask,
  control frame size, fragmentation, the 64-bit length's top bit),
  `WebSocketMessageAssembler` joins fragments and checks UTF-8, and
  `FramedWebSocket` is the `RelicWebSocket` on top: ping and pong, the
  close handshake with a two second wait for the peer's answer, a ping
  interval that closes with 1001 when a pong does not come, and 1006 for
  a connection that drops. `RelicServer` runs the opening handshake over
  `hijack` for an adapter without `capabilities.webSocket`, keeps the
  sockets it framed, and sends them 1001 before the adapter closes.
- IOAdapter is unchanged: `capabilities.webSocket` is true and it keeps
  dart:io's framer.

Deviations from PLAN.md and DESIGN.md:

- The Autobahn test suite was not run. The frame-level rules it checks
  are covered by hand-built vectors in `relic_core/test/web_socket/`,
  and the framer refuses what the suite's strict cases refuse: bad
  UTF-8 is detected at message end rather than per fragment, which the
  RFC allows and Autobahn marks as non-strict.
- No subprotocol negotiation. `WebSocketUpgrade` has no protocols
  argument and the dart:io path selects none either, so `protocol` is
  an empty string on both.
- Closing the channel sink closes the connection whole, after the
  flush, not just the write side. A hijacked connection that wants the
  peer's last bytes after its own close keeps the sink open. The
  framer's close handshake works that way.
- A hijack after a streamed request body that the handler was reading
  gets the bytes that arrive from then on. Chunks already queued for
  the body stream are not carried over.

Measurements, `packages/benchmark/bin/ws_echo.dart`, same machine as
P0, 64 in-process dart:io clients each sending and awaiting one echo at
a time, eight seconds, two runs each:

| adapter and framer | message | round trips/s | p50 ms | p99 ms |
|---|---|---|---|---|
| relic_io, dart:io framer | 64 B text | 12718, 12872 | 4.6 | 10.4 |
| relic_native, Dart framer | 64 B text | 25678, 27142 | 1.9 | 7.0 |
| relic_io, dart:io framer | 1 KiB text | 11030, 10966 | 5.4 | 11.3 |
| relic_native, Dart framer | 1 KiB text | 20482, 20806 | 2.6 | 7.3 |
| relic_io, dart:io framer | 4 KiB binary | 9351 | 6.4 | 14.2 |
| relic_native, Dart framer | 4 KiB binary | 19834 | 2.6 | 8.2 |

The P5 acceptance asked for the Dart framer within 20% of dart:io's on
the 1 KiB text echo. It is at 187%. The clients run in the same process
in both runs, so their cost is the same on both rows and the difference
is the server side: the native adapter's socket path plus the Dart
framer against dart:io's HTTP server plus its framer.

## P6, benchmarks and publication (2026-10-01)

Done. `packages/benchmark/bin/http_load.dart` is the HTTP load harness
and `bin/ws_echo.dart` the WebSocket one. The package docs are in
`packages/relic_native/README.md`: platforms, the Zig requirement for a
source checkout, how to choose between the adapters, and the limits.

The harness serves five workloads through a `RelicApp` (router and the
default pipeline) and drives `oha` from its own process. Per target and
workload it finds the saturation rate with a closed loop of 64
connections, then measures open loop at 50%, 75% and 100% of that rate
with latency correction, so a stalled server is charged for the requests
it made wait. Workloads: `plaintext`, `json`, `headers` (a browser's
seventeen request headers with a 300 byte cookie, the handler reads the
agent, the language and one cookie), `alloc` (4000 short-lived strings
joined per request, for the GC) and `mixed` (one request in a hundred
waits 50 ms).

Deviations from DESIGN.md section 8:

- No ceiling or boundary rows. The P0 spike measured those (see P0),
  and the package has no canned-response mode to measure them again.
- Bun is not on this machine, so it was not measured. The harness takes
  a URL as a target for that comparison.
- CPUs were not pinned. Same machine as P0: 16 cores, macOS 26.6, with
  `oha` 1.12.1 sharing it with the server.

Results, five seconds per run, `io4` and `native4` being four isolates
on one port, the native one with four executors:

| target | workload | load | offered rps | rps | p50 | p99 | p99.9 |
|---|---|---|---|---|---|---|---|
| io | plaintext | 50% | 4756 | 4755 | 0.59 | 2.06 | 3.19 |
| io | plaintext | 75% | 7133 | 7130 | 0.87 | 3.35 | 7.18 |
| io | plaintext | 100% | 9511 | 9508 | 5.23 | 20.94 | 22.89 |
| io | json | 50% | 4875 | 4874 | 0.59 | 1.84 | 8.32 |
| io | json | 75% | 7313 | 7310 | 0.84 | 2.91 | 6.55 |
| io | json | 100% | 9750 | 9748 | 6.74 | 116.69 | 118.39 |
| io | headers | 50% | 3216 | 3216 | 0.61 | 1.42 | 2.52 |
| io | headers | 75% | 4824 | 4664 | 1.00 | 321.16 | 329.65 |
| io | headers | 100% | 6432 | 6430 | 3.63 | 17.89 | 20.33 |
| io | alloc | 50% | 679 | 680 | 1.04 | 2.43 | 2.89 |
| io | alloc | 75% | 1018 | 1018 | 0.87 | 2.63 | 4.80 |
| io | alloc | 100% | 1357 | 1304 | 4.77 | 263.43 | 264.49 |
| io | mixed | 50% | 5383 | 5381 | 0.60 | 8.90 | 52.38 |
| io | mixed | 75% | 8075 | 8073 | 1.14 | 30.33 | 62.39 |
| io | mixed | 100% | 10766 | 10203 | 148.28 | 260.32 | 270.92 |
| io4 | plaintext | 50% | 13281 | 13274 | 0.60 | 1.77 | 4.10 |
| io4 | plaintext | 75% | 19922 | 19914 | 0.86 | 3.93 | 7.23 |
| io4 | plaintext | 100% | 26562 | 25073 | 99.68 | 281.47 | 282.79 |
| io4 | json | 50% | 11892 | 11890 | 0.51 | 1.51 | 2.79 |
| io4 | json | 75% | 17838 | 17834 | 0.69 | 2.15 | 5.21 |
| io4 | json | 100% | 23784 | 23777 | 1.17 | 31.56 | 33.46 |
| io4 | headers | 50% | 8427 | 8424 | 0.58 | 1.65 | 3.19 |
| io4 | headers | 75% | 12640 | 12633 | 0.80 | 3.02 | 5.33 |
| io4 | headers | 100% | 16853 | 16436 | 16.63 | 182.82 | 185.24 |
| io4 | alloc | 50% | 1895 | 1895 | 0.93 | 2.51 | 10.21 |
| io4 | alloc | 75% | 2843 | 2842 | 1.02 | 8.10 | 17.62 |
| io4 | alloc | 100% | 3790 | 3790 | 4.40 | 29.71 | 32.28 |
| io4 | mixed | 50% | 15566 | 15562 | 0.54 | 4.25 | 52.26 |
| io4 | mixed | 75% | 23348 | 23337 | 0.85 | 8.55 | 53.46 |
| io4 | mixed | 100% | 31131 | 28109 | 272.44 | 487.41 | 531.40 |
| native | plaintext | 50% | 26443 | 26432 | 0.73 | 4.81 | 6.48 |
| native | plaintext | 75% | 39665 | 39655 | 1.09 | 6.64 | 9.91 |
| native | plaintext | 100% | 52886 | 52674 | 3.81 | 16.35 | 20.98 |
| native | json | 50% | 24939 | 24928 | 0.74 | 4.42 | 6.19 |
| native | json | 75% | 37408 | 37389 | 1.03 | 5.71 | 8.13 |
| native | json | 100% | 49877 | 49809 | 2.03 | 10.25 | 12.15 |
| native | headers | 50% | 14937 | 14933 | 1.10 | 3.73 | 6.00 |
| native | headers | 75% | 22406 | 22400 | 1.15 | 6.14 | 10.15 |
| native | headers | 100% | 29874 | 29832 | 24.15 | 55.46 | 56.70 |
| native | alloc | 50% | 825 | 825 | 1.03 | 4.38 | 5.53 |
| native | alloc | 75% | 1238 | 1238 | 1.40 | 6.58 | 18.49 |
| native | alloc | 100% | 1650 | 1639 | 78.15 | 124.46 | 130.25 |
| native | mixed | 50% | 26859 | 26837 | 0.75 | 8.54 | 53.05 |
| native | mixed | 75% | 40288 | 40275 | 0.91 | 12.12 | 53.81 |
| native | mixed | 100% | 53717 | 49476 | 59.52 | 399.10 | 400.87 |
| native4 | plaintext | 50% | 53286 | 53271 | 0.70 | 2.76 | 8.83 |
| native4 | plaintext | 75% | 79929 | 79900 | 0.92 | 6.55 | 14.71 |
| native4 | plaintext | 100% | 106572 | 105762 | 2.03 | 25.74 | 35.85 |
| native4 | json | 50% | 52134 | 52113 | 0.68 | 1.81 | 3.86 |
| native4 | json | 75% | 78200 | 78133 | 0.93 | 7.06 | 16.91 |
| native4 | json | 100% | 104267 | 104117 | 29.31 | 49.46 | 50.28 |
| native4 | headers | 50% | 27534 | 27526 | 0.83 | 2.33 | 5.20 |
| native4 | headers | 75% | 41301 | 41291 | 1.06 | 4.29 | 6.18 |
| native4 | headers | 100% | 55068 | 51782 | 312.07 | 339.53 | 343.60 |
| native4 | alloc | 50% | 2434 | 2434 | 1.21 | 4.07 | 18.33 |
| native4 | alloc | 75% | 3650 | 3649 | 1.98 | 9.30 | 25.78 |
| native4 | alloc | 100% | 4867 | 4840 | 28.04 | 53.95 | 60.38 |
| native4 | mixed | 50% | 37864 | 37843 | 0.53 | 50.57 | 52.33 |
| native4 | mixed | 75% | 56795 | 56762 | 0.75 | 50.79 | 52.81 |
| native4 | mixed | 100% | 75727 | 72504 | 112.90 | 214.70 | 223.35 |

Reading it:

- Plaintext and JSON on one isolate: `native` saturates at 52.9K and
  49.9K requests per second against 9.5K and 9.8K for `io`, 5.5 times
  the rate. The percentile columns are not comparable row by row, since
  each row sits at a fraction of its own target's saturation: the
  native 50% row carries 26K rps, the io one 4.8K.
- Headers: 29.9K against 6.4K. The lazy `ByteHeaderStore` reads three
  of the seventeen fields and the rest is never decoded.
- Alloc: 1650 against 1357. The handler's own garbage dominates, and
  the adapters are close. Four isolates take `native4` to 4.9K.
- Mixed: at 50% and 75% load the p99.9 is the 50 ms sleep on every
  target, as designed. At 100% every target queues behind the slow 1%.
- Four isolates: `io4` saturates at 2.8 times `io` on plaintext and
  2.6 times on headers. `native4` reaches 106.6K on plaintext and 55.1K
  on headers, 2.0 and 1.8 times `native`. The first run of the harness
  had `io4` on port 0, which gives each dart:io isolate its own port
  with the server reporting the first, so that row measured one
  isolate. The io targets take a fixed port now.
- The 100% rows are saturation offered open loop, so they show queueing
  on every target. The 50% and 75% rows are the ones to compare.
- `io` at 75% on headers shows a p99 spike of 321 ms in an otherwise
  flat run, and `io` json at 100% a 117 ms p99. The native rows at 50%
  and 75% have none above 13 ms. That is
  the tail the design set out to remove: the native threads keep
  parsing and answering keep-alives through a Dart pause.

Hello world against main, the same route on the tree before this work
(`main`, 2.0.0-rc.2) and after, oha closed loop, 64 connections, five
seconds, best of three:

| server | rps | p50 ms | p99 ms |
|---|---|---|---|
| main, dart:io, 1 isolate | 10255 | 6.07 | 8.66 |
| main, dart:io, 4 isolates | 29998 | 2.09 | 3.23 |
| now, relic_io, 1 isolate | 11456 | 5.35 | 8.18 |
| now, relic_io, 4 isolates | 31061 | 2.01 | 3.29 |
| now, relic_native, 1 isolate | 56916 | 1.06 | 2.19 |
| now, relic_native, 4 isolates | 71177 | 0.86 | 1.68 |

The dart:io path gained about 10% from the exchange refactor and the
lazy headers, on one isolate and on four. The native adapter on one
isolate does 5.5 times what main does on one, and on four isolates 2.4
times what main does on four.

Isolates against executors on the hello route, same setup:

| isolates | executors | rps | p50 ms |
|---|---|---|---|
| 1 | 1 | 56851 | 1.08 |
| 1 | 2 | 70285 | 0.82 |
| 1 | 4 | 70233 | 0.83 |
| 4 | 1 | 55289 | 1.11 |
| 4 | 2 | 74893 | 0.83 |
| 2 | 4 | 103904 | 0.55 |
| 4 | 4 | 109473 | 0.54 |

One executor thread tops out near 56K whatever the isolate count, and
one isolate near 70K whatever the executor count. The two have to grow
together. Four of each reach 109K, within 20% of the P0 ceiling (the
native side answering alone, 116K to 138K) and near the floor that 64
closed-loop connections at 0.5 ms set. The load table's `native4` rows
were first run with two executors and are from four now, and the
harness gives a native target as many executors as isolates.

Up to the core count, 16 on this machine. The hello route, 128
connections closed loop, six seconds, with the server's and oha's CPU
sampled mid-run (100% is one core):

| server | rps | server cpu | oha cpu | server cpu per request |
|---|---|---|---|---|
| native 1 isolate, 1 executor | 56788 | 183% | 175% | 32 us |
| native 2, 2 | 71012 | 359% | 352% | 51 us |
| native 4, 4 | 115371 | 689% | 484% | 60 us |
| native 8, 8 | 109159 | 850% | 444% | 78 us |
| native 16, 16 | 105879 | 903% | 317% | 85 us |
| native 16, 4 | 95650 | 741% | 452% | 78 us |
| dart:io 1 isolate | 10977 | 125% | 54% | 114 us |
| dart:io 4 | 27751 | 444% | 198% | 160 us |
| dart:io 16 | 60473 | 999% | 278% | 165 us |

At 64 connections, best of three, 8/8 gave 104K, 16/16 99K, and at 256
connections 106K and 109K, so the plateau is not a connection count.
Two and three oha processes at once against 16/16 totalled 99K and
82K while the server's CPU fell from 957% to 779%: the generator was
taking the cores the server lost. Past four isolates and four
executors this machine is the limit, server plus client plus kernel on
16 cores, and the number to compare across servers is the CPU per
request. The native adapter costs 32 us per request on one isolate and
dart:io 114 us, 3.5 times as much, and dart:io's cost grows to 165 us
by 16 isolates where the native one grows to 85 us. The native growth
with thread count is not explained yet. Two candidates, both
unmeasured: with the load spread over many isolates each goes idle
between requests, so the one-wake-per-idle-to-busy transition becomes a
wake per request, and more executor threads each own fewer connections,
so each kevent returns fewer events per syscall. A profile at 16/16 is
the next step if the per-request cost at many isolates matters, which
it does once handlers are cheap and isolates are added for throughput.

Other runtimes on the same machine, the same hello route and oha
settings (128 connections closed loop, six seconds, CPU sampled mid-run
over the process and its children), with the relic rows from the sweep
above for reference:

| server | rps | p50 ms | p99 ms | cpu | us cpu per request |
|---|---|---|---|---|---|
| deno 2.9, Deno.serve (hyper, one thread) | 99771 | 1.21 | 2.03 | 100% | 10.0 |
| go 1.27 net/http, GOMAXPROCS=1 | 48580 | 2.57 | 4.45 | 98% | 20.3 |
| go 1.27 net/http, GOMAXPROCS=4 | 120193 | 0.96 | 2.88 | 384% | 32.0 |
| go 1.27 net/http, GOMAXPROCS=16 | 127341 | 0.93 | 2.48 | 756% | 59.4 |
| node 26 http, 1 process | 29899 | 4.03 | 8.18 | 99% | 33.4 |
| node 26 http, 4 cluster workers | 84990 | 1.38 | 3.40 | 402% | 47.3 |
| node 26 http, 16 cluster workers | 111450 | 0.95 | 7.12 | 913% | 81.9 |
| relic_native, 1 isolate, 1 executor | 56788 | | | 183% | 32.3 |
| relic_native, 4, 4 | 115371 | | | 689% | 59.7 |
| relic_io (dart:io), 1 isolate | 10977 | | | 125% | 113.6 |
| relic_io, 16 isolates | 60473 | | | 999% | 165.2 |

Per core, the native adapter is at Node's cost per request, 1.6 times
Go's and 3 times a Rust stack's, and 3.5 times better than dart:io.
Every multi-core row meets the same wall between 110K and 130K, which
is this machine with oha on it, so the single-thread rows and the cost
per request are the comparison. All of it is a hello route on loopback
with the JIT.

Where the 32 us go, from `ps -M` on the one isolate, one executor
server at 58.4K rps: the zio executor thread at 90% of a core, two
thirds of it kernel time, is 15.5 us per request; the isolate's mutator
thread at 68%, nearly all user time, is 11.6 us; a VM helper thread at
23% is 3.9 us. So the Zig side alone costs half again what hyper costs
for a whole request, and most of that is syscalls: recv, send, the
kevent share, and the wake of the isolate that hyper never pays. The
user-side parse and index is about 5 us. The P0 ceiling of 116K was a
canned-response spike with no CPU measured and is not a per-request
cost.

Pure hyper 1 (Rust, tokio, a `service_fn` answering `Hello`, release
build), same settings:

| server | rps | p50 ms | p99 ms | cpu | us cpu per request |
|---|---|---|---|---|---|
| hyper, tokio current_thread | 99659 | 1.14 | 2.01 | 100% | 10.0 |
| hyper, 2 worker threads | 137819 | 0.91 | 1.60 | 195% | 14.2 |
| hyper, 4 worker threads | 152845 | 0.82 | 1.20 | 333% | 21.8 |
| hyper, 8 worker threads | 132854 | 0.95 | 1.26 | 391% | 29.5 |
| hyper, 16 worker threads | 135933 | 0.93 | 1.22 | 405% | 29.8 |

Deno.serve on one thread is hyper on one thread: 99.8K against 99.7K,
10 us per request each, so the JavaScript callback costs nothing
measurable on this route. Hyper's four threads at 153K is the highest
number this machine gave any server, and the ceiling it then meets is
the same box-plus-oha wall, 30 us per request at 16 threads from 10 at
one.

Deno.serve does not scale on macOS: `reusePort` is Linux only, and a
second worker on the port fails with address in use, so the way up is
processes behind a balancer. Inside a Linux container on the same
machine (Docker, 16 virtual CPUs, oha inside the container), one worker
did 36.7K, two 60.7K, four 74.4K, eight 308K and sixteen 323K. The VM
is about three times slower than the host on one worker and the jump
from four to eight workers is not explained, so the shape, not the
numbers, is the finding: on Linux it scales across workers with
`reusePort`, and a real Linux box is needed for the numbers.

## P7, the reactor on the isolate thread (2026-10-01)

Done. Each isolate runs its own zio runtime on its own thread, ticked
from the adapter's event loop, and one acceptor thread per server hands
sockets to the reactor with the fewest connections. The suite is 116
cases on relic_native, everything the previous design passed plus a
keep-alive close case, with nothing skipped. zio's 699 tests pass with
the patch.

Why zio and not std.Io: `std.Io.Kqueue` in Zig 0.16.0 and on master as
of 2026-09-30 has 36 `@panic("TODO")`, among them `netListenIp`,
`netAccept`, `sleep` and `cancel`, and its last substantive commit is
from May. `std.Io.Dispatch` is complete but resumes fibers through a GCD
queue on GCD's threads, which a foreign thread cannot pump. `std.Io.Uring`
is complete and has the same seam, so the Linux half was ready, and the
macOS half would have been the implementation itself. zio's executor
runs the loop whenever its main task blocks, with the calling thread as
executor 0, which is the shape already.

The zio patch (`executor-tick` bookmark, one commit, seven files, about
260 lines):

- `Executor.tick(wait_cap)`: wakes handed out since the last pass, the
  ready tasks, one poll bounded by `wait_cap`, the tasks that
  completions readied, a few times over while the loop keeps handing
  wakes out, then back to the caller. It binds the executor and its
  loop to the calling thread on every call, since a Dart isolate can
  run its next event on another OS thread. Returns whether work remains.
- `Loop.hostHandle`: the kqueue, epoll or ring descriptor a host waits
  on. `Loop.nextTimerDeadline`: the bound on that wait for clocks a
  backend does not arm natively (`.awake` on macOS). `Loop.hasPendingWork`
  and `Loop.hasDispatched`, with `hasPendingChanges` per backend.
- `drainReady` extracted from `Executor.run`, shared by both.

Three of those came from stalls the Dart host hit that `Executor.run`
never sees because it loops: a group member finishing cancels its
siblings, whose completions a poll leaves queued for the next poll; a
task that runs during the drain can finish a completion the loop hands
out inline, which sat in `dispatched` until the next tick; and a kqueue
registration made by a task after the poll sat in the backend's change
buffer, which nothing reported. Each is now in `hasPendingWork`, and the
host ticks again on it.

What the host learned the hard way:

- `Loop.wake` coalesces on a flag that only a real poll clears, and a
  loop with nothing in flight returns from `poll` before that, so a wake
  posted to an idle loop can be the last one that reaches the kernel.
  The waiter thread takes its stop and its re-arm through a pipe.
- A zero `Timer.run` costs 10.5 us and goes through the dart:io event
  handler thread, one for the VM. A message to the isolate's own port
  costs 0.7 us. Measured with a 20K hop chain.
- The build hook tracked only the package's own sources, so an edit in
  the zio checkout did not rebuild the library Dart loads. It tracks the
  Zig sources of every `.path` dependency now.

Measurements, the hello route, 128 connections closed loop unless said,
CPU sampled mid-run with `ps`:

| server | rps | p50 ms | server cpu | us cpu per request |
|---|---|---|---|---|
| P6 design, 1 isolate, 1 executor | 56788 | | 183% | 32.3 |
| P7, 1 isolate | 43449 | 2.46 | 102% | 23.5 |
| P7, 1 isolate, 16 connections | 33841 | 0.43 | 101% | 29.7 |

The go or no-go was 25 us on one thread. One isolate on one core does
43K where one isolate and one executor did 57K on two, 37% better per
core. The linger before the isolate parks (0, 1 and 10 ms) made no
difference at 16 connections.

The sweep that first produced the multi-isolate rows ran while another
job shared the machine's eight physical cores, and the same code gave
one isolate at 16 connections 11K in one run and 34K in the next, so
those rows were dropped. The rerun below, later the same day, reads
CPU as user and system time from `proc_pid_rusage` over the oha window
instead of a `ps` sample, summed over the process tree, after a 2 s
warm-up. The same machine, the same oha settings, 6 s per row. Every
single-thread row, hyper included, came out 15 to 20 percent slower
than the morning's runs for no reason `pmset -g therm` reports, so the
ratios are what to read, not the absolute values.

| server | rps | p50 ms | p99 ms | server cpu | user us | sys us | total us |
|---|---|---|---|---|---|---|---|
| hyper 1.7, 1 thread | 79761 | 1.48 | 2.99 | 99% | 4.9 | 7.5 | 12.4 |
| hyper, 4 threads | 117170 | 1.01 | 2.33 | 302% | 10.7 | 15.1 | 25.7 |
| deno 2.9 Deno.serve | 82059 | 1.46 | 2.68 | 99% | 4.9 | 7.2 | 12.1 |
| go 1.27 net/http, GOMAXPROCS=1 | 42364 | 2.93 | 5.24 | 100% | 14.5 | 9.0 | 23.5 |
| go 1.27 net/http, GOMAXPROCS=16 | 109553 | 1.03 | 3.25 | 656% | 34.0 | 25.8 | 59.8 |
| node 26 http, 1 process | 23574 | 5.12 | 9.91 | 101% | 30.9 | 12.0 | 42.9 |
| node 26 http, 16 cluster workers | 78616 | 0.68 | 21.17 | 780% | 74.7 | 24.5 | 99.2 |
| relic_native, 1 isolate | 39619 | 2.97 | 6.13 | 103% | 16.8 | 9.2 | 26.1 |
| relic_native, 2 isolates | 76224 | 1.56 | 3.66 | 203% | 16.9 | 9.7 | 26.6 |
| relic_native, 4 isolates | 94886 | 1.19 | 4.03 | 364% | 24.2 | 14.1 | 38.3 |
| relic_native, 8 isolates | 73040 | 1.54 | 5.81 | 485% | 42.0 | 24.4 | 66.4 |
| relic_native, 16 isolates | 74296 | 0.99 | 14.20 | 610% | 50.2 | 31.9 | 82.1 |
| relic_io, 1 isolate | 6183 | 19.65 | 32.93 | 126% | 145.0 | 58.7 | 203.7 |
| relic_io, 4 isolates | 20978 | 6.03 | 8.24 | 428% | 146.9 | 57.0 | 203.9 |
| relic_io, 16 isolates | 41359 | 1.87 | 27.26 | 828% | 148.3 | 51.8 | 200.1 |

What the split says:

- The system half is the same 7 to 9 us for every server on this box.
  hyper and Deno tie because the kernel is the bigger half of both;
  Deno's JavaScript is 0.7 to 1 us of user time on top of hyper's.
- relic_native's gap to hyper is all user time: 16.8 against 4.9. Of
  that, measured with stopwatches in the adapter: request construction
  2.0, response encoding 3.1, pipeline and handler 2.6, drain loop and
  FFI glue 1.2, Zig and zio 3.7 (head parse 0.7), GC and the helper
  threads 1.8.
- The second isolate scales at the same cost per request. Past four
  the box is the limit: oha takes about three cores at 100K, and every
  server here, hyper included, lands between 110K and 120K.
- The 30 s write timeout makes zio wrap every send in a race group with
  a timer. The send completes inline, the task continues after the next
  poll settles the timer cancel. The bytes are not delayed, the CPU is:
  a timer arm and cancel per send and recv and an extra resume per
  request. An optimistic submit before the timer is armed is the fix to
  propose for zio.

Deviations from PLAN.md:

- One acceptor thread per server with least-connections dispatch, not
  `SO_REUSEPORT`, since macOS does not balance it.
- The linger is a fixed millisecond. Adaptive waits were not needed for
  the numbers above and are left out.

## Zig 0.17.0 and zio 0.19.0 (2026-10-06)

zio's main moved to Zig 0.17, and the `executor-tick` commits sit on top
of it. `minimum_zig_version`, the CI workflows and `tool/linux/Dockerfile`
follow.

- The Zig sources compile unchanged. The build-step translation of
  `dart_api_dl.h` and the absence of `**` were done for master on
  2026-10-02.
- `zig build` no longer takes `--global-cache-dir`. The build hook and
  `tool/linux_test.dart` passed it and failed with "unrecognized
  argument". Both now set the local cache only. `ZIG_GLOBAL_CACHE_DIR`
  is the replacement, and it was not used: anyzig keeps its compilers
  in the global cache, so the variable makes it download one per cache.
- TSan runs on macOS now. `zig build test -Dsanitize-thread` passes
  there, where 0.16.0 trapped at startup.
- Fuzz mode still does not build on macOS. The test runner compiles,
  and the link fails on `___sanitizer_cov_trace_cmp1` and three more of
  that family, from `dart_api_dl.c`. The seeded sweep stays.
- `tool/linux_test.dart` builds its image on every run. It built only
  when the image was missing, which would have kept the 0.16.0 one.
- zio is no longer a path dependency. `build.zig.zon` pins the
  `executor-tick` branch of `nielsenko/zio` by commit and hash, so a
  source build needs no checkout beside the repo, and
  `tool/linux_test.dart` takes one with `--zio=<path>` only to run
  zio's own suite.
- zio picks its scheduling at build time now (`-Dscheduling`). relic
  takes the default, `work_stealing`, with one executor per runtime.
  `single_executor` compiles the migration code out and measures the
  same, so the default stays.

Server CPU per request on the hello route, 128 connections, four
interleaved 10 s rounds each, microseconds:

| Isolates | work_stealing | single_executor |
|----------|---------------|-----------------|
| 1 | 11.3 (11.0 to 11.7) | 11.6 (11.3 to 11.9) |
| 4 | 26.0 (25.1 to 27.1) | 25.9 (25.3 to 26.9) |

The move itself cost nothing either. One isolate, same method: this
tree on Zig 0.17.0 and zio main 11.5, this tree on Zig 0.16.0 and the
zio 0.18.0 base of 2026-10-02 11.3, the relic tree of 2026-10-02 on that
zio 11.6.

The same build read 16.4 ten minutes earlier, at 60K requests a second
in place of 88K, with the load average no different. A single-isolate
run near 60K on this machine is the machine, not the code.


## The idle linger and answers from a microtask (2026-10-07)

A WebSocket echo ran no faster than shelf. Two causes.

- `bin/ws_echo.dart` ran its dart:io clients in the server's isolate,
  which capped every server near 10K round trips a second. The clients
  have isolates of their own now.
- The drain went into its 1 ms idle linger with the answer still in
  Dart's microtask queue. An echo is written by the framer's stream
  listener and an async handler answers from a continuation, and both
  run only when the drain returns. Each round trip waited out the
  linger: 16 connections made 16K round trips a second, one per
  millisecond each. The drain now ends its turn when it handed an
  exchange to an async handler or dispatched an event, and lingers only
  on a turn that handed Dart nothing. A sync handler has answered
  already and does not end the turn.

Round trips a second, 64 byte text, driven by uWebSockets' `load_test`
(C, built with `zig cc`) against `bin/ws_echo_serve.dart`, on mains
power with the hello route at 86K requests a second before and after:

| Connections | native | shelf | relic_io |
|-------------|--------|-------|----------|
| 16 | 95K | 39K | 40K |
| 64 | 94K | 39K | 40K |

Before the change, on battery and throttled, native made 16K at 16
connections and 54K at 64, against 59K at both after it.

The hello route with its sync handler is unchanged at 1, 8 and 128
connections, measured interleaved.

Where a round trip's 10.6 us go at 94K, from `sample` on the server and
the VM profiler together: `sendto` 36% and `recvfrom` 29% of the
isolate thread, Dart 13% (the framer and the stream plumbing under it),
the reactor tick itself 8%, `kevent` 7%. One receive and one send per
message is two thirds of the cost, the same kernel floor the hello
route sits on. shelf is 2.4 times slower here and about 11 times slower on
hello because dart:io's WebSocket path is lean and its HTTP path is
not.

## One pass over the head (2026-10-07)

`std.http.Server.receiveHead` parsed every head with
`Request.Head.parse` before `indexHead` scanned the same lines again.
The std parser splits on the two-byte CRLF sequence and compares each
field name against six names. In a symbol-level sample of the hello
route that was 4.1% of the isolate thread, `mem.eql` under
`SplitIterator.next`.

`parseHead` does both jobs in the one line scan: the request line, the
framing fields (Connection, Expect, Content-Length, Content-Encoding,
Transfer-Encoding) picked out by name length first, and the slots. The
`std.http.Reader` still finds the end of the head and reads the body,
and the `Request` it needs is built from what `parseHead` read. The
fuzz sweep parses every head with both and fails when they disagree on
one that both accept, or when `parseHead` accepts one std refuses.

Hello on one isolate, four interleaved rounds, total us per request:
11.9 before (11.2 to 12.2), 11.2 after (10.8 to 11.6).

A count of the server's system calls for 600K requests at 128
connections, taken with an interposing library: 600,741 `recvfrom`
with 612 of them EAGAIN, 600,000 `sendto`, 178 `kevent`. One receive
and one send per request, so what separates relic_native from Deno and
hyper on this route is user time.

## One deadline per connection (2026-10-07)

Every timed receive and send went through zio's `timedWaitForIo`, which
races the operation against a timer in a group. With the operation
submitted first the timer is seldom armed, but the group is still
built, submitted and called back, and the header deadline read the
clock: about 3 to 4% of the isolate thread on the hello route.

The idle wait, the head read and the write of a response of up to
64 KiB now run with no zio timeout. A `Conn` on the task's frame holds
a deadline in clock milliseconds, set per phase, and one `sweep` task
per reactor walks the connections every quarter of the shortest
timeout (10 ms to 1 s) and cancels the task of each one past its
deadline. The task sees the cancel as a failed read or write and
answers 408 or closes as before. The sweeper runs only while the
reactor has connections.

Two things to know. zio hands a cancel that lost the race with a
completed operation to the task's next wait, and that must never be the
park, where Dart holds the frame: `Conn.settle` takes it back at every
phase change. And the write timeout is an inactivity limit, which one
deadline can only stand in for on a response a live peer takes in one
go, so a body over 64 KiB keeps the timeout on each send.

The task is cancelled through `main_executor.current_task`, which zio
does not export by name.

Hello on one isolate, five interleaved rounds, total us per request:
11.4 before (11.0 to 11.6), 11.1 after (10.7 to 11.5).

## The response written into the write buffer (2026-10-07)

A response cost two `malloc` and two `free`: Dart allocated a buffer
for the head and one for the body through `relic_alloc`, and the task
copied both into the connection's 16 KiB write buffer and freed them.

The view now carries that write buffer as `scratch` when it is empty.
A response whose head bound and body fit is encoded by Dart straight
into it and answered with `relic_respond_inline`, and the task sends
the buffer as it lies: no allocation, one FFI call in place of three,
and the bytes are written once. A response that does not fit takes the
old path. `ExchangeView` grows from 120 to 136 bytes.

An inline request body is read into one buffer the connection keeps
for its next request while it stays within 64 KiB, in place of an
allocation per request.

Hello on one isolate, five interleaved rounds, total us per request:
11.2 before (10.9 to 11.6), 10.7 after (10.2 to 11.0).

## Four cuts on the Dart side (2026-10-07)

A profile of the hello route after the native work put Dart at 22% of
the isolate thread. End-to-end runs differ by 0.4 us between rounds,
so each cut was measured on its own in a loop of a few million calls,
and the four together end to end.

| Cut | Before | After |
|-----|--------|-------|
| In-flight exchanges in a `LinkedList`, and in the address map only when the native side can post an event for them | 119 ns | 33 ns |
| `Body.consume` in place of `Body.read` for a body sent from its bytes | 44 ns | 0 ns |
| `holdHttpDate` for a drain turn, per response in a turn of 16 | 65 ns | 8 ns |
| `ResponseFraming.of` for a response that sets neither Connection nor Transfer-Encoding | 141 ns | 36 ns |

Hello on one isolate, ten interleaved rounds, total us per request:
10.6 before the four (10.3 to 11.4), 10.1 after (9.9 to 10.6), with
user time down from 4.4 to 3.9. The measured parts add up to 0.3 us of
that 0.5.

A first loop for the bookkeeping gave 663 ns for the set and the map.
Its made-up view addresses were all multiples of 4096 and collided in
the map. With addresses spaced as coroutine stacks are it is 119 ns.

## Why Deno is still ahead on hello (2026-10-08)

Clean numbers from the evening of 2026-10-07, hello on one thread or
isolate, us per request: hyper 8.5 (2.8 user, 5.7 system), Deno 9.3
(3.5, 5.8), relic_native 10.1 (3.9, 6.2). The 0.8 to Deno is half user
time and half system time.

System calls are not the difference. Counted with an interposing
library, Deno makes 400,000 `recvfrom` (one EAGAIN), 399,996 `sendto`
and 6,797 `kevent` for 400,000 requests. relic_native makes one of
each of the first two and fewer `kevent`. The responses are the same
size, 120 and 121 bytes.

User time is the framework. Deno 2.9 does not run this request through
JavaScript in any real sense: a stack sample shows its own HTTP/1 code
(`deno_http_h1` with httparse, `serve_http11_raw`) and a response
written natively (`write_default_text_response`,
`write_h1_flat_response`). V8 and JavaScript are 12% of its user time,
about 0.4 us. relic_native runs the router, builds a `Request`, frames
the response and encodes its head in Dart for every request, about
1.8 us after the cuts above, on top of 1.8 us of Zig and zio. So
relic's managed-language share is four to five times Deno's, and its
native share is already below Deno's.

The 0.4 us of system time is not explained. Same calls, same bytes.
It matches the earlier note that a system call costs more inside the
Dart VM process than in a plain Zig one. Per-call kernel time for both
servers, with dtrace as root, is the measurement that would settle it.

The machine was no use for timing during this: `pmset -g therm` showed
`CPU_Speed_Limit` at 20, on and off, and hyper and Deno both read
24K requests a second at 41 to 44 us in that state.
