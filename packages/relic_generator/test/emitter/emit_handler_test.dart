import 'package:relic_generator/relic_generator.dart';
import 'package:test/test.dart';

void main() {
  group('emitHandlerCode', () {
    test('simple GET endpoint with no parameters', () {
      const model = ApiClassModel(
        className: 'HealthApi',
        basePath: '/api/health',
        endpoints: [
          EndpointModel(
            methodName: 'check',
            httpMethod: HttpMethod.get,
            path: '/',
            returnType: 'Future<String>',
            resolvedReturnType: 'String',
            isVoid: false,
            isAsync: true,
            parameters: [],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(
        code,
        contains('abstract class _\$HealthApi implements RouterInjectable'),
      );
      expect(code, contains('Future<String> check();'));
      expect(code, contains('void injectIn(RelicRouter router)'));
      expect(code, contains("router.get('/'"));
      expect(code, contains('final result = await check();'));
      expect(code, contains('Response.ok('));
      expect(code, contains('jsonEncode(result)'));
      expect(code, contains('MimeType.json'));
    });

    test('GET endpoint with path and query parameters', () {
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
              ParameterModel(
                name: 'includeDetails',
                type: 'bool',
                isNullable: true,
                isRequired: false,
                source: ParameterSource.query,
                sourceName: 'include_details',
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(
        code,
        contains(
          'Future<User> getById({required int id, bool? includeDetails})',
        ),
      );
      expect(code, contains("router.get('/:id'"));
      expect(code, contains('int.parse(req.rawPathParameters[#id]!)'));
      expect(code, contains("req.url.queryParameters['include_details']"));
      expect(code, contains("== 'true'"));
      expect(code, contains('getById(id: id, includeDetails: includeDetails)'));
    });

    test('POST endpoint with @JsonBody', () {
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

      final code = emitHandlerCode(model);

      expect(code, contains("router.post('/'"));
      expect(code, contains('await req.readAsString()'));
      expect(code, contains('jsonDecode(bodyStr) as Map<String, dynamic>'));
      expect(code, contains('CreateUserRequest.fromJson(bodyJson)'));
      expect(code, contains('create(body: body)'));
    });

    test('endpoint with @Status(201)', () {
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
            statusCode: 201,
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

      final code = emitHandlerCode(model);

      expect(code, contains('Response('));
      expect(code, contains('201,'));
      expect(code, isNot(contains('Response.ok(')));
    });

    test('void return type', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'deleteUser',
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

      final code = emitHandlerCode(model);

      expect(code, contains('Future<void> deleteUser({required int id})'));
      expect(code, contains("router.delete('/:id'"));
      expect(code, contains('await deleteUser(id: id);'));
      expect(code, contains('Response.noContent()'));
      expect(code, isNot(contains('jsonEncode')));
    });

    test('void return type with @Status', () {
      const model = ApiClassModel(
        className: 'UsersApi',
        basePath: '/api/users',
        endpoints: [
          EndpointModel(
            methodName: 'archive',
            httpMethod: HttpMethod.post,
            path: '/:id/archive',
            returnType: 'Future<void>',
            resolvedReturnType: 'void',
            isVoid: true,
            isAsync: true,
            statusCode: 202,
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

      final code = emitHandlerCode(model);

      expect(code, contains('Response(202)'));
      expect(code, isNot(contains('Response.noContent()')));
    });

    test('endpoint with @Errors', () {
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
            errors: [ErrorModel(typeName: 'NotFound', statusCode: 404)],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(code, contains('try {'));
      expect(code, contains('on NotFound {'));
      expect(code, contains('rethrow;'));
      expect(code, contains('catch (e, s) {'));
      expect(code, contains('Response.internalServerError()'));
    });

    test('class-level errors propagate to all endpoints', () {
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
        errors: [ErrorModel(typeName: 'Unauthorized', statusCode: 401)],
      );

      final code = emitHandlerCode(model);

      expect(code, contains('on Unauthorized {'));
      expect(code, contains('rethrow;'));
    });

    test('class-level and method-level @Use middleware', () {
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
            middleware: [FunctionMiddlewareRef(expression: 'validateBody')],
          ),
        ],
        middleware: [
          FunctionMiddlewareRef(expression: 'logRequests'),
          ObjectMiddlewareRef(
            expression: 'AuthMiddleware()',
            typeName: 'AuthMiddleware',
          ),
        ],
      );

      final code = emitHandlerCode(model);

      // Class-level middleware
      expect(code, contains("router.use('/', logRequests)"));
      expect(code, contains('router.inject(AuthMiddleware())'));

      // Method-level middleware
      expect(code, contains('Handler innerHandler'));
      expect(code, contains('innerHandler = validateBody(innerHandler)'));
      expect(code, contains('return innerHandler(req)'));
    });

    test('header parameter extraction', () {
      const model = ApiClassModel(
        className: 'AuthApi',
        basePath: '/api/auth',
        endpoints: [
          EndpointModel(
            methodName: 'verify',
            httpMethod: HttpMethod.get,
            path: '/',
            returnType: 'Future<User>',
            resolvedReturnType: 'User',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'token',
                type: 'String',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.header,
                sourceName: 'Authorization',
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(code, contains("req.headers['Authorization']!.first"));
      expect(code, contains('verify(token: token)'));
    });

    test('request parameter is passed directly', () {
      const model = ApiClassModel(
        className: 'ProxyApi',
        basePath: '/api/proxy',
        endpoints: [
          EndpointModel(
            methodName: 'forward',
            httpMethod: HttpMethod.post,
            path: '/',
            returnType: 'Future<Response>',
            resolvedReturnType: 'Response',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'req',
                type: 'Request',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.request,
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      // Request params should be positional in abstract method
      expect(code, contains('Future<Response> forward(Request req)'));
      // Response type returned directly — request params passed positionally
      expect(code, contains('return await forward(req)'));
    });

    test('form body parameter extraction', () {
      const model = ApiClassModel(
        className: 'FormApi',
        basePath: '/api/form',
        endpoints: [
          EndpointModel(
            methodName: 'submit',
            httpMethod: HttpMethod.post,
            path: '/',
            returnType: 'Future<String>',
            resolvedReturnType: 'String',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'formData',
                type: 'Map<String, String>',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.formBody,
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(code, contains('Uri.splitQueryString(bodyStr)'));
    });

    test('String path param needs no parsing', () {
      const model = ApiClassModel(
        className: 'Api',
        basePath: '/api',
        endpoints: [
          EndpointModel(
            methodName: 'getBySlug',
            httpMethod: HttpMethod.get,
            path: '/:slug',
            returnType: 'Future<String>',
            resolvedReturnType: 'String',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'slug',
                type: 'String',
                isNullable: false,
                isRequired: true,
                source: ParameterSource.path,
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(code, contains('req.rawPathParameters[#slug]!'));
      expect(code, isNot(contains('int.parse')));
    });

    test('query parameter with default value', () {
      const model = ApiClassModel(
        className: 'Api',
        basePath: '/api',
        endpoints: [
          EndpointModel(
            methodName: 'list',
            httpMethod: HttpMethod.get,
            path: '/',
            returnType: 'Future<List<String>>',
            resolvedReturnType: 'List<String>',
            isVoid: false,
            isAsync: true,
            parameters: [
              ParameterModel(
                name: 'page',
                type: 'int',
                isNullable: false,
                isRequired: false,
                source: ParameterSource.query,
                hasDefault: true,
                defaultValueCode: '1',
              ),
            ],
          ),
        ],
      );

      final code = emitHandlerCode(model);

      expect(code, contains("req.url.queryParameters['page'] != null"));
      expect(code, contains(': 1;'));
    });
  });
}
