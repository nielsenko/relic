import '../ir/api_class_model.dart';
import '../ir/endpoint_model.dart';
import '../ir/parameter_model.dart';

/// Emits an OpenAPI 3.1 spec fragment for an API class.
///
/// Returns a map representing the `paths` object for this API class,
/// suitable for merging into a complete OpenAPI document.
Map<String, dynamic> emitOpenApiFragment(ApiClassModel model) {
  final paths = <String, dynamic>{};

  for (final endpoint in model.endpoints) {
    final fullPath = _combinePaths(model.basePath, endpoint.path);
    // Convert :param to {param} for OpenAPI format
    final openApiPath = _convertPathParams(fullPath);

    final method = endpoint.httpMethod.name; // 'get', 'post', etc.

    final operation = _buildOperation(endpoint, model);

    // Group operations under the same path
    paths.putIfAbsent(openApiPath, () => <String, dynamic>{});
    (paths[openApiPath] as Map<String, dynamic>)[method] = operation;
  }

  return paths;
}

/// Combines base path and endpoint path.
String _combinePaths(String basePath, String endpointPath) {
  // Normalize: remove trailing slash from base, ensure leading slash on endpoint
  final base = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  final endpoint = endpointPath.startsWith('/')
      ? endpointPath
      : '/$endpointPath';

  if (endpoint == '/') return base.isEmpty ? '/' : base;
  return '$base$endpoint';
}

/// Converts Relic-style :param to OpenAPI {param} format.
String _convertPathParams(String path) {
  return path.replaceAllMapped(
    RegExp(r':(\w+)'),
    (match) => '{${match.group(1)}}',
  );
}

Map<String, dynamic> _buildOperation(
  EndpointModel endpoint,
  ApiClassModel model,
) {
  final operation = <String, dynamic>{
    'operationId': '${model.className}.${endpoint.methodName}',
    'tags': [model.className],
  };

  // Parameters (path, query, header)
  final parameters = <Map<String, dynamic>>[];
  for (final param in endpoint.parameters) {
    if (param.source == ParameterSource.path) {
      parameters.add(_buildParameter(param, 'path'));
    } else if (param.source == ParameterSource.query) {
      parameters.add(_buildParameter(param, 'query'));
    } else if (param.source == ParameterSource.header) {
      parameters.add(_buildParameter(param, 'header'));
    }
  }
  if (parameters.isNotEmpty) {
    operation['parameters'] = parameters;
  }

  // Request body (JsonBody or FormBody)
  final bodyParam = endpoint.parameters
      .where(
        (p) =>
            p.source == ParameterSource.jsonBody ||
            p.source == ParameterSource.formBody,
      )
      .firstOrNull;
  if (bodyParam != null) {
    operation['requestBody'] = _buildRequestBody(bodyParam);
  }

  // Responses
  operation['responses'] = _buildResponses(endpoint, model);

  return operation;
}

Map<String, dynamic> _buildParameter(ParameterModel param, String location) {
  return {
    'name': param.effectiveName,
    'in': location,
    'required': location == 'path' ? true : param.isRequired,
    'schema': _typeToSchema(param.type),
  };
}

Map<String, dynamic> _buildRequestBody(ParameterModel bodyParam) {
  final contentType = bodyParam.source == ParameterSource.jsonBody
      ? 'application/json'
      : 'application/x-www-form-urlencoded';

  return {
    'required': bodyParam.isRequired,
    'content': {
      contentType: {'schema': _typeToSchema(bodyParam.type)},
    },
  };
}

Map<String, dynamic> _buildResponses(
  EndpointModel endpoint,
  ApiClassModel model,
) {
  final responses = <String, dynamic>{};

  // Success response
  final statusCode = endpoint.statusCode ?? (endpoint.isVoid ? 204 : 200);
  final statusStr = statusCode.toString();

  if (endpoint.isVoid) {
    responses[statusStr] = {'description': 'No content'};
  } else {
    responses[statusStr] = {
      'description': 'Successful response',
      'content': {
        'application/json': {
          'schema': _typeToSchema(endpoint.resolvedReturnType),
        },
      },
    };
  }

  // Error responses from @Errors
  final allErrors = [...model.errors, ...endpoint.errors];
  for (final error in allErrors) {
    final errorStatus = (error.statusCode ?? 500).toString();
    if (!responses.containsKey(errorStatus)) {
      responses[errorStatus] = {
        'description': error.typeName,
        'content': {
          'application/json': {
            'schema': {r'$ref': '#/components/schemas/${error.typeName}'},
          },
        },
      };
    }
  }

  return responses;
}

/// Maps a Dart type string to an OpenAPI schema.
Map<String, dynamic> _typeToSchema(String dartType) {
  // Strip nullable suffix
  final type = dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;

  // Primitive type mappings
  switch (type) {
    case 'String':
      return {'type': 'string'};
    case 'int':
      return {'type': 'integer', 'format': 'int64'};
    case 'double':
      return {'type': 'number', 'format': 'double'};
    case 'num':
      return {'type': 'number'};
    case 'bool':
      return {'type': 'boolean'};
    case 'DateTime':
      return {'type': 'string', 'format': 'date-time'};
    case 'void':
      return {};
    case 'dynamic':
    case 'Object':
      return {};
  }

  // List<T> → array
  final listMatch = RegExp(r'^List<(.+)>$').firstMatch(type);
  if (listMatch != null) {
    return {'type': 'array', 'items': _typeToSchema(listMatch.group(1)!)};
  }

  // Map<String, T> → object with additionalProperties
  final mapMatch = RegExp(r'^Map<String,\s*(.+)>$').firstMatch(type);
  if (mapMatch != null) {
    return {
      'type': 'object',
      'additionalProperties': _typeToSchema(mapMatch.group(1)!),
    };
  }

  // Custom type → $ref
  return {r'$ref': '#/components/schemas/$type'};
}
