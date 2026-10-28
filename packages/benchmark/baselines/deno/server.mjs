// The http_load.dart routes on bare Deno.serve, as a floor for the
// relic_fetch builds that run on the same host. With a certificate chain
// and a key it serves HTTPS.
//
//   deno run --allow-net server.mjs 8092
//   dart run bin/http_load.dart --targets=deno=http://127.0.0.1:8092
//   deno run --allow-net --allow-read server.mjs 8443 \
//       ../../../relic_native/test/certs/localhost_cert.pem \
//       ../../../relic_native/test/certs/localhost_key.pem

const port = Number(Deno.args[0] ?? 8092);
if (Deno.args.length === 2) throw new Error('key path missing');
const tls = Deno.args.length > 2
  ? { cert: Deno.readTextFileSync(Deno.args[1]), key: Deno.readTextFileSync(Deno.args[2]) }
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

Deno.serve({ port, ...tls }, (req) => {
  const path = new URL(req.url).pathname;
  const h = req.headers;
  switch (path) {
    case '/plaintext':
      return new Response('Hello, World!');
    case '/headers': {
      const agent = h.get('user-agent') ?? '';
      const languages = h.get('accept-language')?.split(',').length ?? 0;
      const session = cookie(h.get('cookie'), 'session');
      return new Response(`${agent.length} ${languages} ${session?.length ?? 0}`);
    }
    case '/browser': {
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
    }
    default:
      return new Response(null, { status: 404 });
  }
});
