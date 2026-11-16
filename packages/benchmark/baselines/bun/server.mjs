// The http_load.dart routes on bare Bun.serve, beside Deno.serve as a
// second JavaScript runtime. With a certificate chain and a key it serves
// HTTPS. It listens on BENCH_ADDRESS when set.
//
//   bun run server.mjs 8094
//   dart run bin/http_load.dart --targets=bun=http://127.0.0.1:8094
//   bun run server.mjs 8494 \
//       ../../../relic_native/test/certs/localhost_cert.pem \
//       ../../../relic_native/test/certs/localhost_key.pem

const args = Bun.argv.slice(2);
const port = Number(args[0] ?? 8094);
const hostname = process.env.BENCH_ADDRESS ?? '127.0.0.1';
if (args.length === 2) throw new Error('key path missing');
const tls = args.length > 2
  ? { tls: { cert: Bun.file(args[1]), key: Bun.file(args[2]) } }
  : {};
const etag = '"relic-browser-1"';
const items = JSON.stringify(
  Array.from({ length: 20 }, (_, i) => ({
    id: i,
    name: `item ${i}`,
    tags: ['new', 'sale'],
    price: 100 + i,
  })),
);

function cookie(header, name) {
  if (header == null) return null;
  for (const pair of header.split(';')) {
    const at = pair.indexOf('=');
    if (at > 0 && pair.slice(0, at).trim() === name) return pair.slice(at + 1).trim();
  }
  return null;
}

// Bun's own router matches the paths natively, before any JavaScript
// runs. Each route is a function, so every request builds its answer as on
// the other servers, rather than Bun replaying a static Response.
Bun.serve({
  hostname,
  port,
  ...tls,
  routes: {
    '/plaintext': () => new Response('Hello, World!'),
    '/headers': (req) => {
      const h = req.headers;
      const agent = h.get('user-agent') ?? '';
      const languages = h.get('accept-language')?.split(',').length ?? 0;
      const session = cookie(h.get('cookie'), 'session');
      return new Response(`${agent.length} ${languages} ${session?.length ?? 0}`);
    },
    '/browser': (req) => {
      const h = req.headers;
      const host = h.get('host');
      const session = cookie(h.get('cookie'), 'session');
      if (h.get('if-none-match') === etag) {
        return new Response(null, { status: 304, headers: { etag } });
      }
      return new Response(
        `{"host":${JSON.stringify(host)},"session":${JSON.stringify(session)},"items":${items}}`,
        {
          headers: {
            'content-type': 'application/json; charset=utf-8',
            etag,
            'cache-control': 'private, max-age=60',
          },
        },
      );
    },
  },
  fetch() {
    return new Response(null, { status: 404 });
  },
});
