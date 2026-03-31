import 'dart:convert';
import 'package:codable_dart/standard.dart';
import 'package:codable_dart/json.dart';
import 'package:test/test.dart';
import 'package:relic_errors/relic_errors.dart';

void main() {
  group('Codable serialization', () {
    const codable = HttpExceptionCodable();

    test('BadRequestException encodes to map with statusCode and message', () {
      const e = BadRequestException('invalid field');
      final map = e.toMap();
      expect(map, {'statusCode': 400, 'message': 'invalid field'});
    });

    test('NotFoundException encodes to map', () {
      const e = NotFoundException('resource missing');
      final map = e.toMap();
      expect(map, {'statusCode': 404, 'message': 'resource missing'});
    });

    test('InternalServerErrorException encodes to map', () {
      const e = InternalServerErrorException('server crash');
      final map = e.toMap();
      expect(map, {'statusCode': 500, 'message': 'server crash'});
    });

    group('round-trip via Standard (Map)', () {
      final exceptions = <HttpException>[
        const BadRequestException('bad'),
        const UnauthorizedException('unauth'),
        const ForbiddenException('forbidden'),
        const NotFoundException('missing'),
        const ConflictException('conflict'),
        const GoneException('gone'),
        const InternalServerErrorException('error'),
        const ServiceUnavailableException('unavailable'),
      ];

      for (final original in exceptions) {
        test('${original.runtimeType} round-trips through Map', () {
          final map = codable.toMap(original);
          final decoded = codable.fromMap(map);
          expect(decoded.statusCode, original.statusCode);
          expect(decoded.message, original.message);
          expect(decoded.runtimeType, original.runtimeType);
        });
      }
    });

    group('round-trip via JSON', () {
      final exceptions = <HttpException>[
        const BadRequestException('bad'),
        const UnauthorizedException('unauth'),
        const ForbiddenException('forbidden'),
        const NotFoundException('missing'),
        const ConflictException('conflict'),
        const GoneException('gone'),
        const InternalServerErrorException('error'),
        const ServiceUnavailableException('unavailable'),
      ];

      for (final original in exceptions) {
        test('${original.runtimeType} round-trips through JSON', () {
          final json = codable.toJson(original);
          final decoded = codable.fromJson(json);
          expect(decoded.statusCode, original.statusCode);
          expect(decoded.message, original.message);
          expect(decoded.runtimeType, original.runtimeType);
        });
      }
    });

    test('decodes unknown status code to generic exception', () {
      final decoded = codable.fromMap({'statusCode': 418, 'message': 'teapot'});
      expect(decoded.statusCode, 418);
      expect(decoded.message, 'teapot');
    });

    test('toJson produces valid JSON string', () {
      const e = BadRequestException('test');
      final jsonStr = e.toJson();
      final parsed = jsonDecode(jsonStr);
      expect(parsed, isA<Map>());
      expect(parsed['statusCode'], 400);
      expect(parsed['message'], 'test');
    });
  });
}
