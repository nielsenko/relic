import 'dart:convert';

import 'package:relic_core/adapter.dart';
import 'package:relic_core/relic_core.dart';
import 'package:relic_core/src/context/result.dart' show RequestInternal;
import 'package:test/test.dart';

Request _offer(List<String> extensions) => RequestInternal.create(
  Method.get,
  Uri.parse('http://localhost/chat'),
  null,
  headers: Headers.fromMap({
    'upgrade': ['websocket'],
    'connection': ['Upgrade'],
    'sec-websocket-version': ['13'],
    'sec-websocket-key': ['dGhlIHNhbXBsZSBub25jZQ=='],
    if (extensions.isNotEmpty) 'sec-websocket-extensions': extensions,
  }),
);

WebSocketDeflate? _negotiate(
  String offer, {
  WebSocketCompression compression = WebSocketCompression.defaults,
}) => negotiateWebSocketDeflate(_offer([offer]), compression);

void main() {
  group('Given a permessage-deflate offer', () {
    test('when it names no parameter, '
        'then it is accepted with 15-bit windows and context takeover', () {
      final deflate = _negotiate('permessage-deflate')!;

      expect(deflate.serverMaxWindowBits, 15);
      expect(deflate.clientMaxWindowBits, 15);
      expect(deflate.serverNoContextTakeover, isFalse);
      expect(deflate.clientNoContextTakeover, isFalse);
      expect(deflate.headerValue, 'permessage-deflate');
    });

    test('when the client offers to take a window bound, '
        'then the server bounds it with its own setting', () {
      final deflate = _negotiate(
        'permessage-deflate; client_max_window_bits',
        compression: const WebSocketCompression(clientMaxWindowBits: 10),
      )!;

      expect(deflate.clientMaxWindowBits, 10);
      expect(deflate.headerValue, contains('client_max_window_bits=10'));
    });

    test('when the client offers no window bound of its own, '
        'then a server that wants one leaves the extension out', () {
      final deflate = _negotiate(
        'permessage-deflate',
        compression: const WebSocketCompression(clientMaxWindowBits: 10),
      );

      expect(deflate, isNull);
    });

    test('when the client bounds its own window below the server setting, '
        'then the smaller one is agreed', () {
      final deflate = _negotiate(
        'permessage-deflate; client_max_window_bits=9',
        compression: const WebSocketCompression(clientMaxWindowBits: 12),
      )!;

      expect(deflate.clientMaxWindowBits, 9);
    });

    test('when the client bounds the server window, '
        'then the server compresses within it', () {
      final deflate = _negotiate(
        'permessage-deflate; server_max_window_bits="11"',
      )!;

      expect(deflate.serverMaxWindowBits, 11);
      expect(deflate.headerValue, contains('server_max_window_bits=11'));
    });

    test('when the client bounds the server window to 8 bits, '
        'then the offer is skipped', () {
      expect(
        _negotiate('permessage-deflate; server_max_window_bits=8'),
        isNull,
      );
    });

    test('when the client asks for no context takeover either way, '
        'then both are agreed and written back', () {
      final deflate = _negotiate(
        'permessage-deflate; server_no_context_takeover; '
        'client_no_context_takeover',
      )!;

      expect(deflate.serverNoContextTakeover, isTrue);
      expect(deflate.clientNoContextTakeover, isTrue);
      expect(
        deflate.headerValue,
        'permessage-deflate; server_no_context_takeover; '
        'client_no_context_takeover',
      );
    });

    test('when the server setting asks for no context takeover, '
        'then it is written back whatever the client offered', () {
      final deflate = _negotiate(
        'permessage-deflate',
        compression: const WebSocketCompression(
          serverNoContextTakeover: true,
          clientNoContextTakeover: true,
        ),
      )!;

      expect(deflate.headerValue, contains('server_no_context_takeover'));
      expect(deflate.headerValue, contains('client_no_context_takeover'));
    });

    test('when a parameter is unknown, repeated or out of range, '
        'then the offer is skipped', () {
      expect(_negotiate('permessage-deflate; foo'), isNull);
      expect(
        _negotiate(
          'permessage-deflate; server_no_context_takeover; '
          'server_no_context_takeover',
        ),
        isNull,
      );
      expect(
        _negotiate('permessage-deflate; client_max_window_bits=16'),
        isNull,
      );
      expect(
        _negotiate('permessage-deflate; client_max_window_bits=x'),
        isNull,
      );
      expect(
        _negotiate('permessage-deflate; server_no_context_takeover=1'),
        isNull,
      );
    });

    test('when it is not permessage-deflate, then nothing is agreed', () {
      expect(_negotiate('x-webkit-deflate-frame'), isNull);
    });
  });

  group('Given several offers', () {
    test('when the first cannot be honoured, then the next one is taken', () {
      final deflate = negotiateWebSocketDeflate(
        _offer([
          'permessage-deflate; server_max_window_bits=8, '
              'permessage-deflate; server_max_window_bits=12',
        ]),
        WebSocketCompression.defaults,
      )!;

      expect(deflate.serverMaxWindowBits, 12);
    });

    test('when they come on separate header lines, then both are read', () {
      final deflate = negotiateWebSocketDeflate(
        _offer(['x-foo', 'permessage-deflate']),
        WebSocketCompression.defaults,
      );

      expect(deflate, isNotNull);
    });

    test('when there is no offer at all, then nothing is agreed', () {
      expect(
        negotiateWebSocketDeflate(_offer([]), WebSocketCompression.defaults),
        isNull,
      );
    });
  });

  test('Given agreed terms, when the handshake response is written, '
      'then it carries them in Sec-WebSocket-Extensions', () {
    final deflate = _negotiate(
      'permessage-deflate; client_no_context_takeover',
    )!;

    final response = utf8.decode(
      webSocketHandshakeResponse(
        's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
        deflate: deflate,
      ),
    );

    expect(
      response,
      contains(
        'Sec-WebSocket-Extensions: permessage-deflate; '
        'client_no_context_takeover\r\n',
      ),
    );
  });
}
