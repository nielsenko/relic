/// The request headers the browser workloads send.
library;

/// What a browser sends, Cookie included, for the headers workload.
const browserWithValidator = [
  ...browserHeaders,
  'If-None-Match: "33a64df551425fcc55e4d42a148795d9f25f89d4"',
];

const browserHeaders = [
  'Host: localhost',
  'Connection: keep-alive',
  'Cache-Control: max-age=0',
  'sec-ch-ua: "Chromium";v="130", "Google Chrome";v="130"',
  'sec-ch-ua-mobile: ?0',
  'sec-ch-ua-platform: "macOS"',
  'Upgrade-Insecure-Requests: 1',
  'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,image/apng,*/*;q=0.8',
  'Sec-Fetch-Site: same-origin',
  'Sec-Fetch-Mode: navigate',
  'Sec-Fetch-User: ?1',
  'Sec-Fetch-Dest: document',
  'Referer: http://localhost/',
  'Accept-Encoding: gzip, deflate, br, zstd',
  'Accept-Language: en-US,en;q=0.9,da;q=0.8',
  'Cookie: session=0123456789abcdef0123456789abcdef0123456789abcdef; '
      '_ga=GA1.1.1234567890.1700000000; _gid=GA1.1.0987654321.1700000000; '
      'theme=dark; consent=analytics,marketing; '
      'tracker=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
];
