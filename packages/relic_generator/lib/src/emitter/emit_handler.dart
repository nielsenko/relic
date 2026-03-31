import 'package:dart_style/dart_style.dart';

import '../ir/api_class_model.dart';
import '../ir/endpoint_model.dart';
import '../ir/error_model.dart';
import '../ir/parameter_model.dart';

final _formatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

/// Generates Dart source code for the `_$FooApi` abstract class
/// that implements `RouterInjectable`.
String emitHandlerCode(ApiClassModel model, {String? sourceFileName}) {
  final className = '_\$${model.className}';
  final abstractMethods = model.endpoints.map(_abstractMethod).join('\n');
  final classMiddleware = model.middleware.map(_classMiddlewareCall).join('\n');
  final endpointRegistrations = model.endpoints
      .map((e) => _endpointRegistration(e, model.errors))
      .join('\n');

  final header = sourceFileName != null
      ? "// GENERATED CODE - DO NOT MODIFY BY HAND\n\npart of '$sourceFileName';\n\n"
      : '';

  final code =
      '''
${header}abstract class $className implements RouterInjectable {
$abstractMethods

@override
void injectIn(RelicRouter router) {
$classMiddleware
$endpointRegistrations
}
}
''';

  return _formatter.format(code);
}

// ---------------------------------------------------------------------------
// Abstract method stubs
// ---------------------------------------------------------------------------

String _abstractMethod(EndpointModel endpoint) {
  final requestParams = endpoint.parameters
      .where((p) => p.source == ParameterSource.request)
      .map((p) => '${p.type} ${p.name}');

  final namedParams = endpoint.parameters
      .where((p) => p.source != ParameterSource.request)
      .map(_namedParamDecl);

  final positional = requestParams.join(', ');
  final named = namedParams.join(', ');

  final paramStr = switch ((positional.isNotEmpty, named.isNotEmpty)) {
    (true, true) => '$positional, {$named}',
    (false, true) => '{$named}',
    (true, false) => positional,
    (false, false) => '',
  };

  return '${endpoint.returnType} ${endpoint.methodName}($paramStr);';
}

String _namedParamDecl(ParameterModel p) {
  final prefix = p.isRequired ? 'required ' : '';
  final nullSuffix = p.isNullable ? '?' : '';
  final defaultPart = p.hasDefault ? ' = ${p.defaultValueCode}' : '';
  return '$prefix${p.type}$nullSuffix ${p.name}$defaultPart';
}

// ---------------------------------------------------------------------------
// Class-level middleware
// ---------------------------------------------------------------------------

String _classMiddlewareCall(MiddlewareRef mw) => switch (mw) {
  FunctionMiddlewareRef(:final expression) => "router.use('/', $expression);",
  ObjectMiddlewareRef(:final expression) => 'router.inject($expression);',
};

// ---------------------------------------------------------------------------
// Endpoint registration
// ---------------------------------------------------------------------------

String _endpointRegistration(
  EndpointModel endpoint,
  List<ErrorModel> classErrors,
) {
  final method = endpoint.httpMethod.name;
  final path = endpoint.path;
  final isAsync = endpoint.isAsync || _needsAwait(endpoint);
  final asyncKeyword = isAsync ? 'async ' : '';

  final body = endpoint.middleware.isNotEmpty
      ? _middlewareWrappedBody(endpoint, classErrors)
      : _handlerBody(endpoint, classErrors);

  return "router.$method('$path', (req) $asyncKeyword{ $body });";
}

// ---------------------------------------------------------------------------
// Handler body (with or without middleware wrapping)
// ---------------------------------------------------------------------------

String _middlewareWrappedBody(
  EndpointModel endpoint,
  List<ErrorModel> classErrors,
) {
  final isAsync = endpoint.isAsync || _needsAwait(endpoint);
  final asyncKeyword = isAsync ? 'async ' : '';
  final inner = _handlerBody(endpoint, classErrors);

  final middlewareApply = endpoint.middleware.map(
    (mw) => switch (mw) {
      FunctionMiddlewareRef(:final expression) =>
        'innerHandler = $expression(innerHandler);',
      ObjectMiddlewareRef(:final expression) =>
        'innerHandler = $expression.call(innerHandler);',
    },
  );

  return '''
Handler innerHandler = (req) $asyncKeyword{ $inner };
${middlewareApply.join('\n')}
return innerHandler(req);
''';
}

String _handlerBody(EndpointModel endpoint, List<ErrorModel> classErrors) {
  final allErrors = [...classErrors, ...endpoint.errors];
  final paramExtractions = endpoint.parameters
      .map(_parameterExtraction)
      .join('\n');
  final methodCall = _methodCall(endpoint);
  final coreBody = '$paramExtractions\n$methodCall';

  if (allErrors.isEmpty) return coreBody;

  final catchClauses = allErrors
      .map((e) => 'on ${e.typeName} { rethrow; }')
      .join('\n');

  return '''
try {
$coreBody
}
$catchClauses
catch (e, s) {
print('[relic] Unhandled exception in ${endpoint.methodName}: \$e');
print(s);
return Response.internalServerError();
}
''';
}

// ---------------------------------------------------------------------------
// Parameter extraction
// ---------------------------------------------------------------------------

String _parameterExtraction(ParameterModel param) {
  final name = param.name;
  final effectiveName = param.effectiveName;

  return switch (param.source) {
    ParameterSource.path =>
      'final $name = ${_parseExpr(param.type, 'req.rawPathParameters[#$effectiveName]!')};',
    ParameterSource.query => _queryExtraction(param),
    ParameterSource.header =>
      param.isNullable || !param.isRequired
          ? "final $name = req.headers['$effectiveName']?.first;"
          : "final $name = req.headers['$effectiveName']!.first;",
    ParameterSource.jsonBody =>
      '''
final bodyStr = await req.readAsString();
final bodyJson = jsonDecode(bodyStr) as Map<String, dynamic>;
final $name = ${param.type}.fromJson(bodyJson);
''',
    ParameterSource.formBody =>
      '''
final bodyStr = await req.readAsString();
final $name = Uri.splitQueryString(bodyStr);
''',
    ParameterSource.request => '', // req is passed directly
  };
}

String _queryExtraction(ParameterModel param) {
  final name = param.name;
  final effectiveName = param.effectiveName;
  final rawCheck = "req.url.queryParameters['$effectiveName']";
  final parsed = _parseExpr(param.type, '$rawCheck!');

  if (param.isNullable || !param.isRequired) {
    final fallback = param.hasDefault ? param.defaultValueCode! : 'null';
    return 'final $name = $rawCheck != null ? $parsed : $fallback;';
  }

  return 'final $name = $parsed;';
}

// ---------------------------------------------------------------------------
// Method call + response
// ---------------------------------------------------------------------------

String _methodCall(EndpointModel endpoint) {
  final args = endpoint.parameters
      .map((p) {
        if (p.source == ParameterSource.request) return 'req';
        return '${p.name}: ${p.name}';
      })
      .join(', ');

  final call = '${endpoint.methodName}($args)';
  final awaitPrefix = endpoint.isAsync ? 'await ' : '';

  if (endpoint.isVoid) {
    final response = endpoint.statusCode != null
        ? 'return Response(${endpoint.statusCode});'
        : 'return Response.noContent();';
    return '$awaitPrefix$call;\n$response';
  }

  if (endpoint.resolvedReturnType == 'Response') {
    return 'return $awaitPrefix$call;';
  }

  const responseBody =
      'body: Body.fromString(jsonEncode(result), mimeType: MimeType.json,)';
  final response = endpoint.statusCode != null
      ? 'return Response(${endpoint.statusCode}, $responseBody,);'
      : 'return Response.ok($responseBody,);';

  return 'final result = $awaitPrefix$call;\n$response';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _parseExpr(String type, String rawExpr) => switch (type) {
  'String' => rawExpr,
  'int' => 'int.parse($rawExpr)',
  'double' => 'double.parse($rawExpr)',
  'num' => 'num.parse($rawExpr)',
  'bool' => "$rawExpr == 'true'",
  _ => '$type.parse($rawExpr)',
};

bool _needsAwait(EndpointModel endpoint) => endpoint.parameters.any(
  (p) =>
      p.source == ParameterSource.jsonBody ||
      p.source == ParameterSource.formBody,
);
