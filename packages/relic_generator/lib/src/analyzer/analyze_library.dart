import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../ir/api_class_model.dart';
import '../ir/endpoint_model.dart';
import '../ir/error_model.dart';
import '../ir/parameter_model.dart';
import 'annotation_reader.dart';

/// Analyzes a library element and extracts all @Api annotated classes as IR
/// models.
List<ApiClassModel> analyzeLibrary(LibraryElement library) {
  final models = <ApiClassModel>[];

  for (final classElement in library.classes) {
    if (hasAnnotation(classElement, 'Api')) {
      models.add(_analyzeApiClass(classElement));
    }
  }

  return models;
}

ApiClassModel _analyzeApiClass(ClassElement classElement) {
  final apiAnnotation = getAnnotation(classElement, 'Api')!;
  final basePath = apiAnnotation.getField('path')!.toStringValue()!;

  final endpoints = <EndpointModel>[];
  final middleware = <MiddlewareRef>[];
  final errors = <ErrorModel>[];

  // Read class-level @Use annotations.
  for (final metadata in classElement.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == 'Use') {
      final value = metadata.computeConstantValue();
      if (value != null) {
        middleware.add(_readMiddlewareRef(value, metadata));
      }
    }
  }

  // Read class-level @Errors.
  final errorsAnnotation = getAnnotation(classElement, 'Errors');
  if (errorsAnnotation != null) {
    errors.addAll(_readErrors(errorsAnnotation));
  }

  // Read methods.
  for (final method in classElement.methods) {
    if (method.isStatic || method.isPrivate) continue;

    final endpoint = _tryAnalyzeEndpoint(method);
    if (endpoint != null) {
      endpoints.add(endpoint);
    }
  }

  return ApiClassModel(
    className: classElement.name ?? '',
    basePath: basePath,
    endpoints: endpoints,
    middleware: middleware,
    errors: errors,
  );
}

EndpointModel? _tryAnalyzeEndpoint(MethodElement method) {
  HttpMethod? httpMethod;
  String? path;

  for (final (annotName, hm) in [
    ('Get', HttpMethod.get),
    ('Post', HttpMethod.post),
    ('Put', HttpMethod.put),
    ('Delete', HttpMethod.delete),
    ('Patch', HttpMethod.patch),
  ]) {
    final annotation = getAnnotation(method, annotName);
    if (annotation != null) {
      httpMethod = hm;
      path = annotation.getField('path')!.toStringValue()!;
      break;
    }
  }

  if (httpMethod == null || path == null) return null;

  // Analyze return type.
  final returnType = method.returnType;
  final returnTypeStr = returnType.getDisplayString();

  DartType resolvedType = returnType;
  bool isAsync = false;
  if (returnType.isDartAsyncFuture || returnType.isDartAsyncFutureOr) {
    isAsync = true;
    resolvedType = (returnType as InterfaceType).typeArguments.first;
  }

  final resolvedReturnTypeStr = resolvedType.getDisplayString();
  final isVoid = resolvedType is VoidType;

  // Analyze parameters.
  final parameters = <ParameterModel>[];
  for (final param in method.formalParameters) {
    parameters.add(_analyzeParameter(param));
  }

  // Method-level @Use.
  final middleware = <MiddlewareRef>[];
  for (final metadata in method.metadata.annotations) {
    final annotElement = metadata.element;
    if (annotElement is ConstructorElement &&
        annotElement.enclosingElement.name == 'Use') {
      final value = metadata.computeConstantValue();
      if (value != null) {
        middleware.add(_readMiddlewareRef(value, metadata));
      }
    }
  }

  // Method-level @Errors.
  final errors = <ErrorModel>[];
  final errorsAnnotation = getAnnotation(method, 'Errors');
  if (errorsAnnotation != null) {
    errors.addAll(_readErrors(errorsAnnotation));
  }

  // @Status.
  int? statusCode;
  final statusAnnotation = getAnnotation(method, 'Status');
  if (statusAnnotation != null) {
    statusCode = statusAnnotation.getField('code')!.toIntValue();
  }

  return EndpointModel(
    methodName: method.name ?? '',
    httpMethod: httpMethod,
    path: path,
    returnType: returnTypeStr,
    resolvedReturnType: resolvedReturnTypeStr,
    isVoid: isVoid,
    isAsync: isAsync,
    parameters: parameters,
    middleware: middleware,
    errors: errors,
    statusCode: statusCode,
  );
}

ParameterModel _analyzeParameter(FormalParameterElement param) {
  final type = param.type;
  final typeStr = type.getDisplayString();
  final isNullable = type.nullabilitySuffix == NullabilitySuffix.question;

  ParameterSource source = ParameterSource.query;
  String? sourceName;

  if (hasAnnotation(param, 'Path')) {
    source = ParameterSource.path;
    sourceName = getAnnotation(
      param,
      'Path',
    )?.getField('name')?.toStringValue();
  } else if (hasAnnotation(param, 'Query')) {
    source = ParameterSource.query;
    sourceName = getAnnotation(
      param,
      'Query',
    )?.getField('name')?.toStringValue();
  } else if (hasAnnotation(param, 'Header')) {
    source = ParameterSource.header;
    sourceName = getAnnotation(
      param,
      'Header',
    )?.getField('name')?.toStringValue();
  } else if (hasAnnotation(param, 'JsonBody')) {
    source = ParameterSource.jsonBody;
  } else if (hasAnnotation(param, 'FormBody')) {
    source = ParameterSource.formBody;
  } else if (hasAnnotation(param, 'Req')) {
    source = ParameterSource.request;
  }

  return ParameterModel(
    name: param.name ?? '',
    type: typeStr,
    isNullable: isNullable,
    isRequired: param.isRequired,
    source: source,
    sourceName: sourceName,
    hasDefault: param.hasDefaultValue,
    defaultValueCode: param.defaultValueCode,
  );
}

MiddlewareRef _readMiddlewareRef(
  DartObject useAnnotation,
  ElementAnnotation metadata,
) {
  final middlewareField = useAnnotation.getField('middleware')!;
  final middlewareType = middlewareField.type!;

  // Extract the middleware argument source from the annotation AST.
  // The annotation source looks like `@Use(someExpression)`.
  final source = metadata.toSource();
  final middlewareSource = _extractUseArgument(source);

  if (isFunctionMiddleware(middlewareType)) {
    return FunctionMiddlewareRef(
      expression:
          middlewareSource ??
          middlewareField.toFunctionValue()?.name ??
          'unknown',
    );
  } else if (isMiddlewareObjectSubtype(middlewareType)) {
    return ObjectMiddlewareRef(
      expression: middlewareSource ?? middlewareType.getDisplayString(),
      typeName: (middlewareType as InterfaceType).element.name ?? '',
    );
  }

  // Fallback: treat as function middleware.
  return FunctionMiddlewareRef(
    expression: middlewareSource ?? middlewareType.getDisplayString(),
  );
}

/// Extracts the argument from a `@Use(...)` annotation source string.
/// Given `@Use(logRequests)`, returns `logRequests`.
/// Given `@Use(AuthMiddleware(role: 'admin'))`, returns `AuthMiddleware(role: 'admin')`.
String? _extractUseArgument(String source) {
  final useIdx = source.indexOf('Use(');
  if (useIdx == -1) return null;
  final start = useIdx + 4; // skip 'Use('

  // Find the matching closing paren.
  int depth = 1;
  int i = start;
  while (i < source.length && depth > 0) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') depth--;
    if (depth > 0) i++;
  }

  if (depth == 0) {
    return source.substring(start, i).trim();
  }
  return null;
}

List<ErrorModel> _readErrors(DartObject errorsAnnotation) {
  final typesList = errorsAnnotation.getField('types')!.toListValue()!;
  return typesList.map((dartObj) {
    final typeValue = dartObj.toTypeValue();
    final typeName = typeValue?.getDisplayString() ?? 'Unknown';

    int? statusCode;
    if (typeValue is InterfaceType) {
      statusCode = _discoverStatusCode(typeValue.element);
    }

    return ErrorModel(typeName: typeName, statusCode: statusCode);
  }).toList();
}

/// Discovers the `statusCode` int value from a class element.
///
/// Tries multiple strategies:
/// 1. Look for a concrete getter named `statusCode` with an int literal body.
/// 2. Look for a static const field named `statusCode`.
int? _discoverStatusCode(InterfaceElement element) {
  // Strategy 1: Look for a concrete getter returning an int literal.
  final getter = element.getGetter('statusCode');
  if (getter != null && !getter.isAbstract) {
    final fragment = getter.firstFragment;
    final session = getter.library.session;
    final parsedResult = session.getParsedLibraryByElement(getter.library);
    if (parsedResult is ParsedLibraryResult) {
      final declaration = parsedResult.getFragmentDeclaration(fragment);
      if (declaration?.node case final ast.MethodDeclaration method) {
        if (method.body case final ast.ExpressionFunctionBody body) {
          if (body.expression case final ast.IntegerLiteral literal) {
            return literal.value;
          }
        }
      }
    }
  }

  // Strategy 2: Static const field.
  final field = element.getField('statusCode');
  if (field != null && field.isStatic && field.isConst) {
    final constValue = field.computeConstantValue();
    return constValue?.toIntValue();
  }

  return null;
}
