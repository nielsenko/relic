# Relic native adapter, implementation plan

Read `DESIGN.md` first. Decisions there (D1-D12) are settled. Open questions
are marked OPEN.

## Ground rules for the implementer

- Work in the Relic monorepo (`serverpod/relic`), one jj change per task,
  with `jj new` before starting on the next one. Never push.
- `melos test` must pass at the end of every phase. No behaviour change for
  `relic_io` users unless this plan names one.
- `relic_core` and `relic_headers` stay free of `dart:io` and FFI (WASM
  story).
- Verify before building on it. Anything marked *(verify)* is an assumption
  from design discussions, not checked in code. Confirm it, and if it is
  wrong, stop and write down the delta before continuing.
- Benchmark claims need numbers from `packages/benchmark`, not intuition.
- Apply the house skills: `human` for every comment, doc and message,
  `comments` before writing any comment (a name, an assert or a type beats
  prose), `conventional-commits` for every jj description, and
  `serverpod-tests` for every test (Given/When/Then names, one flat test
  unless a `setUp` is shared).
- No section-divider banner comments in source files. The sketches under
  `sketches/` still have them and must not be copied as-is.
- Each phase ends with a short entry in `doc/design/relic_native/NOTES.md`:
  what changed, measurements, deviations from `DESIGN.md`.

## Release timing

P1 and P2 are breaking and land in the 2.0.0 release-candidate series
(DESIGN section 9). 2.0.0 final does not ship until both are in. P3 onwards
are additive 2.x work.

---

## P0, spikes and go/no-go (throwaway code, separate change)

Done 2026-10-01, verdict go. See `NOTES.md`.

Goal: kill the plan cheaply if the boundary eats the gain.

1. Compile the Zig sketch against Zig 0.16.0 and zio v0.18.0. Fix the
   `std.http` API names *(verify: `receiveHead`, `head_buffer`,
   `iterateHeaders`, `readerExpectNone`, `HttpConnectionClosing`)*. Record the
   actual API in `NOTES.md`.
2. Foreign-thread `Event.set` from a non-zio thread wakes a parked fiber
   correctly under load *(zio has tests for this. Confirm with a
   1M-iteration stress test)*.
3. Ceiling: native-only canned response. Measure req/s and p99.
4. Boundary: a minimal Dart isolate using the FFI surface (`relic_poll`,
   `relic_respond`, raw pre-encoded response bytes, no Relic). Compare with
   the ceiling and with `dart:io` `HttpServer` doing the same. This spike
   already needs the vendored `dart_api_dl.c` (DESIGN 6.5), so copy it in
   here.
5. Isolate thread-hopping check: log `gettid()` per drain in a spawned
   isolate, to confirm the design does not depend on thread identity (it
   should not, since only the I/O thread uses zio).

Go criteria:

- Boundary throughput at least 1.5x `dart:io` on plaintext.
- p99 at 75% load no worse than `dart:io`'s.

Report the numbers either way. If it is no-go, stop and report.

---

## P1, core adapter interface refactor (`relic_core`, `relic_io`)

Done 2026-10-01. See `NOTES.md`.

Goal: the interface from DESIGN 5.1, 5.2 and 5.8, with `IOAdapter` migrated
and no user-visible change beyond the renamed types.

Tasks:

1. Introduce `Adapter.start(ExchangeSink)`, `AdapterExchange`,
   `AdapterCapabilities`, `Listener`, `HttpProtocol`, `ExchangeEnd`,
   `cancelled` and `done`.
2. Move `respond`, `hijack` and `connect` onto the exchange. Keep
   `Adapter.port` as a deprecated getter derived from `listeners` for one
   release. Change `HijackCallback` to `StreamChannel<Uint8List>`.
3. Rewrite `RelicServer` dispatch per DESIGN 5.8:
   - resolve the adapter once,
   - no `await` on the sync path,
   - delete `_wrapHandlerWithMiddleware`, moving its exception-to-status
     mapping into `_fail`,
   - `_fail` falls back to abort,
   - keep one server-level guarded zone.
4. Move the `Date` header into `respond`. `IOAdapter` sets it from a
   per-second cached value when the response has none.
5. Migrate `IOAdapter` and `io_serve.dart`. At this phase `IOAdapter` may
   still build headers and body eagerly.
6. Add the error-channel tests from DESIGN 7, including "the error response
   itself fails, so abort" and the sync and async variants of each mapped
   exception.
7. Extract the adapter behaviour tests from `packages/relic/test` and
   `packages/relic_io/test/web_socket` into a conformance suite
   parameterized by adapter factory, in `test_utils`. Run it against
   `IOAdapter`. The "malformed target gives 400" test joins the suite here,
   even though the validation only moves in P2.
8. Micro-benchmark: sync handler dispatch overhead before and after (Relic
   pipeline with a trivial handler, in-process fake adapter).

Acceptance:

- All existing tests pass.
- The conformance suite runs.
- The sync handler path has zero awaits. Assert it with a fake adapter that
  checks `respond` was called before `_handle` returned.
- The benchmark shows no regression.
- CHANGELOG entries for the renamed and removed types.

---

## P2, header primitives and lazy request model (`relic_headers`, `relic_core`)

Done 2026-10-01. See `NOTES.md` for the deviations.

Goal: DESIGN 5.3 to 5.6, with no adapter-specific code in core, and header
primitives another package can depend on alone.

Tasks:

1. New workspace package `packages/relic_headers`, no dependencies beyond
   the SDK, same version as the other packages. Contents: `HeaderName`, the
   interning, `HeaderStore`, `MutableHeaderStore` and `MapHeaderStore`.
   Nothing from the codec or caching side.
2. Generate the `HeaderName` table from the standard headers Relic already
   knows (`headers/typed`, `standard_headers_extensions.dart`). Include
   `lookup(String)` and `lookupBytes(bytes, start, end)`, with no allocation
   for known names (perfect hash or length-plus-first-byte switch, the
   implementer's choice, benchmark it). `==` and `hashCode` go over the
   lowercase string so unknown names work as map keys.
3. `HeaderStore` and `MutableHeaderStore` as base classes with a four-member
   abstract core and derived defaults, `newMutable()` and `toMutable()`, and
   `MapHeaderStore` (DESIGN 5.3). The CR/LF/NUL check moves from
   `MutableHeaders` into `MutableHeaderStore`. `ByteHeaderStore` goes in
   `relic_core`, not the package.
4. Re-base `Headers` and `MutableHeaders` on the stores (DESIGN 5.4):
   - `HeaderAccessor<T>` extends `ReadOnlyAccessor<T, HeaderName, Iterable<String>>`
     and adds the encode side,
   - `Headers` gets `get`, `call`, `tryGet` and a per-instance cache keyed by
     accessor. `get` throws `MissingHeaderException`, a failed decode throws
     `InvalidHeaderException`. The `Expando` cache and the `Header<T>`
     extension type go,
   - `Headers.transform` builds on `toMutable()`,
   - `MutableHeaders.set(accessor, value)` replaces `Headers.x[mh].set(...)`,
   - generalize `AccessorState` to wrap a lookup instead of a `Map`,
   - keep the named getters and setters as generated sugar,
   - drop the `Map` interface, keep `[]` by string for custom headers.
5. `HeaderCodec` gains an optional byte decoder. Wire it for
   `content-length`, `content-type` and `host`. List the rest as follow-ups
   in `NOTES.md`.
6. `RequestTarget` (bytes-first, DESIGN 5.5). Remove the eager validation in
   the `Request` constructor. Make `Request.url` lazy. `IOAdapter` answers a
   malformed target with 400.
7. `Body.bytes` (D10), `BodySource` and the sealed `ResponseBody`. The
   `Body`-to-`ResponseBody` mapping lives in core.
8. The router keeps matching on `String` paths in this phase. OPEN:
   byte-level route matching is a later optimization, do not do it now.
9. Tests per DESIGN 7 (header tests), plus `Body.fromString` and
   `Body.fromData` exposing `bytes` and mapping to `BytesBody`.
10. Micro-benchmark: allocations and time per request for a realistic
    18-header request, reading 3 headers vs all headers.

Acceptance:

- Existing tests pass.
- Lazy access to 3 of 18 headers allocates at most 4 Strings (measure via
  `dart:developer` or allocation profiling).
- A package that depends on `relic_headers` alone can build a response
  store with `MapHeaderStore` and read any `HeaderStore` through the base
  class (a smoke test in the package's own `example/`). The package's
  `pubspec.yaml` has no dependency on `relic_core`.
- CHANGELOG entries for the `Headers` API change, the URL-validation change
  and the new package.

---

## P3, `relic_native` MVP (new package `packages/relic_native`)

Done 2026-10-01. See `NOTES.md`.

Goal: HTTP/1.1 with Content-Length bodies, keep-alive, multi-isolate, passing
the conformance suite except the hijack and WebSocket cases.

Tasks:

1. Package skeleton, copied from `serverpod_argon2` (DESIGN 6.8):
   - `build.zig`, `build.zig.zon` pinning `minimum_zig_version = "0.16.0"`
     and zio `v0.18.0`,
   - `src/` for the Zig sources and `src/dart-dl/` for the vendored Dart DL
     API,
   - `hook/build.dart` with prebuilt-or-source resolution and the exact
     version or anyzig rule, `lib/src/native_target.dart`,
     `tool/build_binaries.dart`,
   - no asset and no error on unsupported targets, `@TestOn('linux || mac-os')`
     on the package's tests,
   - `lib/` for the Dart side.
2. Native: implement DESIGN 6.1 to 6.5 starting from
   `sketches/relic_native.zig`:
   - the registry keyed by group token, with attach and detach,
   - `relic_server_listeners` so attachers learn the resolved port,
   - `relic_alloc` and `relic_free`,
   - `relic_abort`,
   - single-executor or pinned zio runtime,
   - idempotent `relic_init_dart_api`.
3. Native limits returning proper status codes:
   - max head size (default 16 KiB) gives 431,
   - max header count gives 431,
   - body over the inline limit without streaming support gives 413 (until
     P4),
   - malformed request line or target gives 400.
4. Dart:
   - FFI bindings, generated or hand-written with a layout test against the
     Zig `extern struct`,
   - `NativeAdapter.bind(address, port:, group:)`,
   - `NativeExchange` (copies head plus slots to a `Uint8List` at dequeue and
     wraps it in `ByteHeaderStore` and `RequestTarget`),
   - the drain loop with batch and yield tuning (DESIGN 6.3),
   - response encoding straight into `relic_alloc` memory (status line,
     headers via `forEach` on any `HeaderStore`, cached per-second `Date`,
     pre-encoded constant headers),
   - only if the P3 benchmark shows head encoding on the profile: a
     write-side encoding store returned from the request store's
     `newMutable()`, with a memcpy path in `respond` when it receives one.
     Record the measurement in `NOTES.md` either way.
5. `serve()` extension mirroring `relic_io`'s `io_serve.dart`. It mints the
   group token per call so `noOfIsolates` works with port 0.
6. Graceful and force `close()` per DESIGN 6.6, excluding peer-disconnect
   detection.
7. CI: run the conformance suite against `NativeAdapter` on linux-x64 and
   macos-arm64 with `mlugg/setup-zig@v2`. Move the coverage cell to
   `stable`. Add `publish.yaml` for the prebuilt binaries.
8. Zig tests: MPSC stress, lost-wake stress, registry with port 0.

Acceptance:

- Conformance suite green (hijack and WebSocket cases skipped by capability).
- Zig tests green.
- Two isolates on port 0 share one server and one port.
- The P0 boundary numbers are reproduced through the full Relic pipeline,
  within 20% of the P0 boundary.
- `melos run test` stays green on the Windows CI cell.

---

## P4, production hardening

Done 2026-10-01. See `NOTES.md` for what the fuzzer found and the soak
numbers.

Tasks:

1. Timeouts via `zio.withTimeout`: header deadline (default 10 s), idle
   keep-alive (default 60 s), body read inactivity (default 30 s). All
   configurable.
2. Streaming bodies, both directions:
   - Request: chunked and large bodies stream to Dart through per-exchange
     SPSC chunk rings, with credit-based backpressure (the fiber stops
     reading when Dart has not consumed N chunks).
   - Response: `StreamBody` chunks pass to native the same way, using chunked
     encoding when there is no content-length.
3. Peer disconnect while parked: the fiber waits on `done` or EOF (zio
   `select`). Map EOF to `exchange.cancelled`.
4. Connection limits: max connections, with accept backpressure.
5. `connectionsInfo` via `relic_server_stats`.
6. Fuzz the request path (DESIGN 7). Fix everything found.
7. Sanitizer CI job (nightly).
8. Error-path tests: slowloris, peer reset mid-response, handler never
   responding (drain timeout triggers abort), and a streaming response
   failing after headers were sent (must end in abort, not a 500).

Acceptance:

- All of the above tested.
- 24 h soak test with mixed traffic, with no RSS growth beyond warm-up and no
  fd leaks.

---

## P5, hijack and WebSocket

Done 2026-10-01. See `NOTES.md`.

Decided (D12): native `hijack()` gives Dart a raw `StreamChannel<Uint8List>`,
with the fiber pumping socket to and from SPSC rings. The RFC 6455 handshake
and framing live in `relic_core` on top of that channel, so every adapter
without a native framer shares them.

Tasks:

1. Native hijack: detach the connection from the keep-alive loop, pump bytes
   both ways, honour close from either side.
2. `relic_core` WebSocket: handshake (including the origin check that
   `RelicServer._isOriginAllowed` does today), frame encoder and decoder,
   masking check, ping/pong, close handshake, `RelicWebSocket`
   implementation over the channel. Test against the Autobahn vectors.
3. `IOAdapter` keeps using `dart:io`'s framer through `capabilities.webSocket`
   and `upgradeWebSocket()`.
4. Enable the conformance cases that P3 skipped.

Acceptance:

- Conformance suite fully green on both adapters.
- The Dart framer's throughput is within 20% of `dart:io`'s on a 1 KiB text
  echo benchmark.

---

## P6, benchmarks and publication

Done 2026-10-01. See `NOTES.md` for the numbers.

1. HTTP load harness in `packages/benchmark` per DESIGN 8 (open-loop,
   percentiles, workloads). Compare `relic_io`, `relic_native` (1 and N
   isolates) and Bun.
2. Write up the results: throughput and tail latency, including where Bun
   wins.
3. Package docs:
   - supported platforms,
   - build requirements (Zig version, anyzig),
   - how to choose between the adapters,
   - known limitations (no TLS, h1 only).

---

## P7, the reactor on the isolate thread

Done 2026-10-01 on zio rather than std.Io. See `NOTES.md`: `std.Io.Kqueue`
in Zig 0.16 and master is a skeleton with no accept, listen or sleep,
and `std.Io.Dispatch` runs fibers on GCD threads, so the std path would
have meant writing the macOS implementation first. zio is complete on
both platforms, its author takes contributions, and its executor already
runs the loop whenever the main task blocks, so the patch is a bounded
`Executor.tick`. The patch is on the `executor-tick` branch of
`nielsenko/zio` and relic_native pins a commit of it until it is
upstream.

Decided on 2026-10-01 after the per-thread cost split in the P6 notes:
the executor thread costs 15.5 us per request against the isolate's
11.6, two thirds of it syscalls including the wake of the isolate, and
isolates and executors had to scale one to one. Deno's shape, one thread
owning both the reactor and the runtime, removes the wake and the second
thread.

Steps, as first planned:

1. Spike. Vendor the two implementations into `src/`, keep the diff to
   those entries, and drive `std.http.Server` from `relic_tick` on the
   isolate thread: connection fibers park on a per-exchange futex, the
   tick returns the ready exchanges, `respond` wakes the fiber, the next
   tick writes. A parked helper thread waits on the kqueue descriptor,
   which is itself pollable, and posts one wake per idle period.
   Go or no-go: the hello route at or under 25 us of server CPU per
   request on one thread, against 32 across two today.
2. Multiple isolates: one `Io` per isolate, an acceptor isolate handing
   file descriptors to the least loaded one, or `SO_REUSEPORT` on Linux.
3. The conformance suite, the fuzzer, the soak and the load table on it.
4. Upstream the two entries to ziglang/zig as a proposal first, with the
   spike and the wake cost as the case: any host with its own loop (Dart,
   Python, Node, a frame loop) needs them. Keep the vendored copy until a
   pinned Zig release carries them.

The fallback is hyper on a tokio `current_thread` runtime driven the same
way, which Deno does. It costs the toolchain switch and buys httparse,
rustls and h2.

## Later (not planned in detail)

- Zero-copy request bodies (finalizer-backed `asTypedList`).
- `sendfile` for `FileBody`.
- Byte-level router matching.
- HTTP/2 (nghttp2), TLS (BoringSSL), HTTP/3 (quic-zig plus nghttp3, shared
  with Keldris) and WebTransport.
- Windows (zio IOCP).
