import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

void main() {
  group('TransferEncodingHeader.parse', () {
    group('Given a valid multi-coding value,', () {
      test('when parsed, '
          'then the encodings are preserved in order.', () {
        final header = TransferEncodingHeader.parse(['gzip, chunked']);

        expect(
          header.encodings.map((final e) => e.name),
          equals(['gzip', 'chunked']),
        );
      });
    });

    group('Given "chunked" is not the last coding,', () {
      test(
        'when parsed, '
        'then the encodings are reordered so chunked is last (RFC 9112 6.1).',
        () {
          final header = TransferEncodingHeader.parse(['chunked, gzip']);

          expect(
            header.encodings.map((final e) => e.name),
            equals(['gzip', 'chunked']),
          );
        },
      );
    });

    group('Given duplicate codings,', () {
      test('when parsed, '
          'then duplicates are removed.', () {
        final header = TransferEncodingHeader.parse(['gzip, chunked, chunked']);

        expect(
          header.encodings.map((final e) => e.name),
          equals(['gzip', 'chunked']),
        );
      });
    });

    group('Given a value that contains "chunked",', () {
      test('when parsed, '
          'then chunked is among the encodings.', () {
        final header = TransferEncodingHeader.parse(['gzip, chunked']);

        expect(
          header.encodings.any(
            (final e) => e.name == TransferEncoding.chunked.name,
          ),
          isTrue,
        );
      });
    });

    group('Given an invalid coding,', () {
      test('when parsed, '
          'then it throws a FormatException stating the value is invalid.', () {
        expect(
          () => TransferEncodingHeader.parse(['custom-encoding']),
          throwsA(
            isA<FormatException>().having(
              (final e) => e.message,
              'message',
              contains('Invalid value'),
            ),
          ),
        );
      });
    });

    group('Given an empty value,', () {
      test(
        'when parsed, '
        'then it throws a FormatException stating the value cannot be empty.',
        () {
          expect(
            () => TransferEncodingHeader.parse(['']),
            throwsA(
              isA<FormatException>().having(
                (final e) => e.message,
                'message',
                contains('Value cannot be empty'),
              ),
            ),
          );
        },
      );
    });
  });

  group('TransferEncodingHeader encoding', () {
    group('Given a valid header with chunked last,', () {
      test('when encoded, '
          'then the codings render in order.', () {
        final header = TransferEncodingHeader.parse(['gzip, chunked']);

        expect(
          TransferEncodingHeader.codec.encode(header),
          equals(['gzip, chunked']),
        );
      });
    });
  });
}
