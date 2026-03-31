import 'package:test/test.dart';
import 'package:relic_errors/relic_errors.dart';

void main() {
  group('HttpException subtypes', () {
    test('BadRequestException has status 400', () {
      const e = BadRequestException('bad input');
      expect(e.statusCode, 400);
      expect(e.message, 'bad input');
    });

    test('UnauthorizedException has status 401', () {
      const e = UnauthorizedException('no token');
      expect(e.statusCode, 401);
      expect(e.message, 'no token');
    });

    test('ForbiddenException has status 403', () {
      const e = ForbiddenException('access denied');
      expect(e.statusCode, 403);
      expect(e.message, 'access denied');
    });

    test('NotFoundException has status 404', () {
      const e = NotFoundException('not found');
      expect(e.statusCode, 404);
      expect(e.message, 'not found');
    });

    test('ConflictException has status 409', () {
      const e = ConflictException('duplicate');
      expect(e.statusCode, 409);
      expect(e.message, 'duplicate');
    });

    test('GoneException has status 410', () {
      const e = GoneException('removed');
      expect(e.statusCode, 410);
      expect(e.message, 'removed');
    });

    test('InternalServerErrorException has status 500', () {
      const e = InternalServerErrorException('oops');
      expect(e.statusCode, 500);
      expect(e.message, 'oops');
    });

    test('ServiceUnavailableException has status 503', () {
      const e = ServiceUnavailableException('down');
      expect(e.statusCode, 503);
      expect(e.message, 'down');
    });

    test('all exceptions implement Exception', () {
      const exceptions = <HttpException>[
        BadRequestException('a'),
        UnauthorizedException('b'),
        ForbiddenException('c'),
        NotFoundException('d'),
        ConflictException('e'),
        GoneException('f'),
        InternalServerErrorException('g'),
        ServiceUnavailableException('h'),
      ];
      for (final e in exceptions) {
        expect(e, isA<Exception>());
        expect(e, isA<HttpException>());
      }
    });

    test('toString includes type, statusCode, and message', () {
      const e = NotFoundException('page not found');
      expect(e.toString(), contains('404'));
      expect(e.toString(), contains('page not found'));
    });
  });
}
