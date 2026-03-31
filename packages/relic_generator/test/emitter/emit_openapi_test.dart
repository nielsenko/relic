import 'package:relic_generator/relic_generator.dart';
import 'package:test/test.dart';

void main() {
  group('emitOpenApiFragment', () {
    test('simple GET endpoint', () {
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
      );

      final result = emitOpenApiFragment(model);

      expect(result, containsPair('/api/users', isA<Map>()));
      final pathItem = result['/api/users'] as Map<String, dynamic>;
      expect(pathItem, containsPair('get', isA<Map>()));

      final op = pathItem['get'] as Map<String, dynamic>;
      expect(op['operationId'], 'UsersApi.list');
      expect(op['tags'], ['UsersApi']);

      final responses = op['responses'] as Map<String, dynamic>;
      expect(responses, containsPair('200', isA<Map>()));
    });

    test('GET with path parameter', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'getById',
            httpMethod: HttpMethod.get,
            path: '/:id',
            returnType: 'Future<User>',
            resolvedReturnType: 'User',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'id',
                type: 'int',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.path,
              ),
            ],
          ),
        ],
      );

      final result = emitOpenApiFragment(model);

      // Path should use {id} not :id
      expect(result, containsPair('/api/users/{id}', isA<Map>()));

      final op =
          (result['/api/users/{id}'] as Map)['get'] as Map<String, dynamic>;
      final params = op['parameters'] as List;
      expect(params, hasLength(1));
      final param = params[0] as Map<String, dynamic>;
      expect(param['name'], 'id');
      expect(param['in'], 'path');
      expect(param['required'], true);
      expect(param['schema'], {'type': 'integer', 'format': 'int64'});
    });

    test('GET with query parameters', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'search',
            httpMethod: HttpMethod.get,
            path: '/search',
            returnType: 'Future<List<User>>',
            resolvedReturnType: 'List<User>',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'q',
                type: 'String',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.query,
              ),
              ParameterModel(
                name: 'limit',
                type: 'int?',
                isNullable: true,
                isRequired: false,
                source: ParameterSource.query,
              ),
            ],
          ),
        ],
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/api/users/search'] as Map)['get'] as Map;
      final params = op['parameters'] as List;
      expect(params, hasLength(2));
    });

    test('POST with JSON body', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'create',
            httpMethod: HttpMethod.post,
            path: '/',
            returnType: 'Future<User>',
            resolvedReturnType: 'User',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'body',
                type: 'CreateUserRequest',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.jsonBody,
              ),
            ],
          ),
        ],
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/api/users'] as Map)['post'] as Map;
      final requestBody = op['requestBody'] as Map<String, dynamic>;
      expect(requestBody['required'], true);
      expect(
        requestBody['content'],
        containsPair('application/json', isA<Map>()),
      );
    });

    test('void return type produces 204', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'delete',
            httpMethod: HttpMethod.delete,
            path: '/:id',
            returnType: 'Future<void>',
            resolvedReturnType: 'void',
            isVoid: true,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'id',
                type: 'int',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.path,
              ),
            ],
          ),
        ],
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/api/users/{id}'] as Map)['delete'] as Map;
      final responses = op['responses'] as Map;
      expect(responses, containsPair('204', isA<Map>()));
    });

    test('custom @Status code', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'create',
            httpMethod: HttpMethod.post,
            path: '/',
            returnType: 'Future<User>',
            resolvedReturnType: 'User',
            isVoid: false,
            isAsync: true,
            parameters: [],
            statusCode: 201,
          ),
        ],
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/api/users'] as Map)['post'] as Map;
      expect(op['responses'], containsPair('201', isA<Map>()));
    });

    test('error responses from @Errors', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'getById',
            httpMethod: HttpMethod.get,
            path: '/:id',
            returnType: 'Future<User>',
            resolvedReturnType: 'User',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'id',
                type: 'int',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.path,
              ),
            ],
            errors: [
              ErrorModel(typeName: 'NotFound', statusCode: 404),
              ErrorModel(typeName: 'Forbidden', statusCode: 403),
            ],
          ),
        ],
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/api/users/{id}'] as Map)['get'] as Map;
      final responses = op['responses'] as Map;
      expect(responses, containsPair('404', isA<Map>()));
      expect(responses, containsPair('403', isA<Map>()));
    });

    test('_typeToSchema maps types correctly', () {
      // Test via the fragment - check response schema for List<User>
      const model = ApiClassModel(
        className: 'TestApi',
        basePath: '/test',
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
      );

      final result = emitOpenApiFragment(model);
      final op = (result['/test'] as Map)['get'] as Map;
      final content =
          ((op['responses'] as Map)['200'] as Map)['content'] as Map;
      final schema = (content['application/json'] as Map)['schema'] as Map;
      expect(schema['type'], 'array');
      expect(schema['items'], {r'$ref': '#/components/schemas/User'});
    });
  });
}
