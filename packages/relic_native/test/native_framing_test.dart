import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import 'native_test_helpers.dart';

Response _ok(final Request _) => Response.ok(body: Body.fromString('ok'));

void main() {
  late RelicServer server;

  setUp(() async => server = await serveNative(_ok));
  tearDown(() => server.close(force: true));

  Future<String> send(final String head) => rawExchange(server, head);

  test('Given a head with bare LF line endings, when it is sent, '
      'then the server answers 400 and closes', () async {
    final reply = await send('GET / HTTP/1.1\nHost: x\n\n');

    expect(reply, startsWith('HTTP/1.1 400'));
  });

  test('Given a head whose last line ends in a bare LF, when it is sent, '
      'then the server answers 400 and closes', () async {
    final reply = await send('GET / HTTP/1.1\r\nHost: x\r\n\n');

    expect(reply, startsWith('HTTP/1.1 400'));
  });

  test('Given a method relic has no Method for, when it is sent, '
      'then the server answers 400 and closes', () async {
    final reply = await send('QUERY / HTTP/1.1\r\nHost: x\r\n\r\n');

    expect(reply, startsWith('HTTP/1.1 400'));
  });

  test('Given a header line with no colon, when it is sent, '
      'then the server answers 400 and closes', () async {
    final reply = await send('GET / HTTP/1.1\r\nHost: x\r\nD\r\n\r\n');

    expect(reply, startsWith('HTTP/1.1 400'));
  });

  test('Given a folded header line, when it is sent, '
      'then the server answers 400 and closes', () async {
    final reply = await send('GET / HTTP/1.1\r\nHost: x\r\n y\r\n\r\n');

    expect(reply, startsWith('HTTP/1.1 400'));
  });

  test('Given a CRLF framed head, when it is sent, '
      'then the request is served', () async {
    final reply = await send(
      'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n',
    );

    expect(reply, startsWith('HTTP/1.1 200'));
    expect(reply, endsWith('ok'));
  });
}
