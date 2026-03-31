import 'package:relic_generator/relic_generator.dart';
import 'package:test/test.dart';

void main() {
  group('ApiClassModel', () {
    test('can be constructed with all fields', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'list',
            httpMethod: HttpMethod.get,
            path: '/',
            returnType: 'Future<List<User>>',
            resolvedReturnType: 'List<User>',
            isVoid: false,
            isAsync: true,
            parameters: [],
          ),
        ],
        middleware: [
          FunctionMiddlewareRef(expression: 'logRequests'),
          ObjectMiddlewareRef(
            expression: 'AuthMiddleware()',
            typeName: 'AuthMiddleware',
          ),
        ],
        errors: [ErrorModel(typeName: 'NotFound', statusCode: 404)],
      );

      expect(model.className, 'UsersApi');
      expect(model.basePath, '/api/users');
      expect(model.endpoints, hasLength(1));
      expect(model.middleware, hasLength(2));
      expect(model.errors, hasLength(1));
    });

    test('defaults middleware and errors to empty lists', () {
      const model = ApiClassModel(
        className: 'SimpleApi',
        basePath: '/api/simple',
        endpoints: [],
      );

      expect(model.middleware, isEmpty);
      expect(model.errors, isEmpty);
    });
  });

  group('EndpointModel', () {
    test('can be constructed with required fields only', () {
      const model = EndpointModel(
        methodName: 'getById',
        httpMethod: HttpMethod.get,
        path: '/:id',
        returnType: 'Future<User>',
        resolvedReturnType: 'User',
        isVoid: false,
        isAsync: true,
        parameters: [],
      );

      expect(model.methodName, 'getById');
      expect(model.httpMethod, HttpMethod.get);
      expect(model.path, '/:id');
      expect(model.middleware, isEmpty);
      expect(model.errors, isEmpty);
      expect(model.statusCode, isNull);
    });

    test('can be constructed with all optional fields', () {
      const model = EndpointModel(
        methodName: 'create',
        httpMethod: HttpMethod.post,
        path: '/',
        returnType: 'Future<User>',
        resolvedReturnType: 'User',
        isVoid: false,
        isAsync: true,
        parameters: [],
        middleware: [FunctionMiddlewareRef(expression: 'validate')],
        errors: [ErrorModel(typeName: 'BadRequest', statusCode: 400)],
        statusCode: 201,
      );

      expect(model.statusCode, 201);
      expect(model.middleware, hasLength(1));
      expect(model.errors, hasLength(1));
    });
  });

  group('ParameterModel', () {
    test('effectiveName returns sourceName when provided', () {
      const model = ParameterModel(
        name: 'id',
        type: 'int',
        isNullable: false,
        isRequired: true,
        source: ParameterSource.path,
        sourceName: 'user_id',
      );

      expect(model.effectiveName, 'user_id');
    });

    test('effectiveName returns name when sourceName is null', () {
      const model = ParameterModel(
        name: 'id',
        type: 'int',
        isNullable: false,
        isRequired: true,
        source: ParameterSource.path,
      );

      expect(model.effectiveName, 'id');
    });

    test('defaults hasDefault to false and defaultValueCode to null', () {
      const model = ParameterModel(
        name: 'limit',
        type: 'int',
        isNullable: true,
        isRequired: false,
        source: ParameterSource.query,
      );

      expect(model.hasDefault, isFalse);
      expect(model.defaultValueCode, isNull);
    });
  });

  group('MiddlewareRef', () {
    test('FunctionMiddlewareRef is a MiddlewareRef', () {
      const ref = FunctionMiddlewareRef(expression: 'logRequests');
      expect(ref, isA<MiddlewareRef>());
      expect(ref.expression, 'logRequests');
    });

    test('ObjectMiddlewareRef is a MiddlewareRef', () {
      const ref = ObjectMiddlewareRef(
        expression: 'AuthMiddleware()',
        typeName: 'AuthMiddleware',
      );
      expect(ref, isA<MiddlewareRef>());
      expect(ref.expression, 'AuthMiddleware()');
      expect(ref.typeName, 'AuthMiddleware');
    });

    test('sealed class discrimination works via switch', () {
      final refs = <MiddlewareRef>[
        const FunctionMiddlewareRef(expression: 'log'),
        const ObjectMiddlewareRef(expression: 'Auth()', typeName: 'Auth'),
      ];

      final results = <String>[];
      for (final ref in refs) {
        switch (ref) {
          case FunctionMiddlewareRef(:final expression):
            results.add('fn:$expression');
          case ObjectMiddlewareRef(:final typeName):
            results.add('obj:$typeName');
        }
      }

      expect(results, ['fn:log', 'obj:Auth']);
    });
  });

  group('Enums', () {
    test('HttpMethod has all expected values', () {
      expect(HttpMethod.values, hasLength(5));
      expect(
        HttpMethod.values.map((e) => e.name),
        containsAll(['get', 'post', 'put', 'delete', 'patch']),
      );
    });

    test('ParameterSource has all expected values', () {
      expect(ParameterSource.values, hasLength(6));
      expect(
        ParameterSource.values.map((e) => e.name),
        containsAll([
          'path',
          'query',
          'header',
          'jsonBody',
          'formBody',
          'request',
        ]),
      );
    });
  });

  group('ErrorModel', () {
    test('can be constructed with required fields only', () {
      const model = ErrorModel(typeName: 'NotFound');
      expect(model.typeName, 'NotFound');
      expect(model.statusCode, isNull);
    });

    test('can be constructed with status code', () {
      const model = ErrorModel(typeName: 'Forbidden', statusCode: 403);
      expect(model.typeName, 'Forbidden');
      expect(model.statusCode, 403);
    });
  });
}
