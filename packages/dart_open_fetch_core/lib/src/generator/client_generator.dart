import '../diagnostic.dart';
import '../ir/api_operation.dart';
import '../ir/api_parameter.dart';
import '../ir/api_schema.dart';
import '../ir/api_spec.dart';
import 'name_resolver.dart';
import 'parameter_serializer.dart';

/// A generated client class with its source code.
class GeneratedClient {
  const GeneratedClient({
    required this.className,
    required this.source,
  });

  final String className;
  final String source;
}

/// Generates typed HTTP client classes from ApiOperation IR nodes.
///
/// Operations are grouped by tag into separate client classes:
/// - Operations with tags → `{Tag}Client`
/// - Operations with no tags → `DefaultClient`
/// - Operations with multiple tags → first tag's client (no duplication)
/// - If no operations have tags → single `{ApiTitle}Client`
class ClientGenerator {
  ClientGenerator({
    required this.nameResolver,
    required this.parameterSerializer,
  });

  final NameResolver nameResolver;
  final ParameterSerializer parameterSerializer;
  final List<Diagnostic> diagnostics = [];

  /// Generate all client classes from the spec.
  ///
  /// Returns a list of generated client classes, each with class name and source.
  List<GeneratedClient> generateClients(ApiSpec spec) {
    // Collect all operations with their path templates
    final allOps = <_OperationWithPath>[];
    for (final path in spec.paths) {
      for (final op in path.operations) {
        allOps.add(_OperationWithPath(path.path, op));
      }
    }

    if (allOps.isEmpty) return [];

    // Group operations by tag
    final grouped = <String, List<_OperationWithPath>>{};
    var anyHasTags = false;

    for (final entry in allOps) {
      if (entry.operation.tags.isNotEmpty) {
        anyHasTags = true;
        // First tag only (no duplication)
        final tag = entry.operation.tags.first;
        grouped.putIfAbsent(tag, () => []).add(entry);
      } else {
        grouped.putIfAbsent('Default', () => []).add(entry);
      }
    }

    // If no operations have tags, use a single client named after the API
    if (!anyHasTags) {
      final clientName = _deriveClientName(spec.info.title);
      return [
        _generateClientClass(clientName, allOps, spec),
      ];
    }

    // Generate one client class per tag group
    final clients = <GeneratedClient>[];
    for (final entry in grouped.entries) {
      final clientName = '${_upperCamelCase(entry.key)}Client';
      clients.add(_generateClientClass(clientName, entry.value, spec));
    }
    return clients;
  }

  GeneratedClient _generateClientClass(
    String className,
    List<_OperationWithPath> operations,
    ApiSpec spec,
  ) {
    final baseUrl = spec.info.baseUrl;
    final buf = StringBuffer();

    buf.writeln("import 'dart:convert';");
    buf.writeln();
    buf.writeln(
        "import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';");
    buf.writeln();

    buf.writeln('class $className {');

    // Constructor
    buf.writeln('  $className({');
    buf.writeln('    required HttpAdapter adapter,');
    buf.writeln('    List<Middleware> middleware = const [],');
    if (baseUrl.isNotEmpty) {
      buf.writeln("    this.baseUrl = '$baseUrl',");
    } else {
      buf.writeln('    required this.baseUrl,');
    }
    buf.writeln('  }) : _chain = MiddlewareChain(adapter, middleware);');
    buf.writeln();

    // Fields
    buf.writeln('  final MiddlewareChain _chain;');
    buf.writeln('  final String baseUrl;');
    buf.writeln();

    // Methods
    for (final entry in operations) {
      _writeOperationMethod(buf, entry.pathTemplate, entry.operation);
      buf.writeln();
    }

    buf.writeln('}');

    return GeneratedClient(className: className, source: buf.toString());
  }

  void _writeOperationMethod(
    StringBuffer buf,
    String pathTemplate,
    ApiOperation operation,
  ) {
    final methodName = NameResolver.resolveFieldName(operation.operationId);
    final successResponse = operation.successResponse;
    final jsonSchema = successResponse?.jsonSchema;

    // Determine return type
    final String returnType;
    final bool hasTypedResponse;
    if (jsonSchema != null) {
      final dartType = _schemaToDartType(jsonSchema);
      returnType = 'Future<ApiResponse<$dartType>>';
      hasTypedResponse = true;
    } else {
      returnType = 'Future<HttpResponse>';
      hasTypedResponse = false;
    }

    // Deprecated annotation
    if (operation.deprecated) {
      buf.writeln("  @Deprecated('Deprecated in API spec')");
    }

    // Method signature
    buf.write('  $returnType $methodName(');
    final params = _buildMethodParams(operation);
    if (params.isNotEmpty) {
      buf.writeln('{');
      for (final p in params) {
        buf.writeln('    $p,');
      }
      buf.write('  }');
    }
    buf.writeln(') async {');

    // Build URL
    _writeUrlConstruction(buf, pathTemplate, operation);

    // Build headers
    _writeHeaderConstruction(buf, operation);

    // Build body
    final bodyVarName = _writeBodySerialization(buf, operation);

    // Build and send request
    buf.writeln("    final request = HttpRequest(");
    buf.writeln("      method: '${operation.method.toUpperCase()}',");
    buf.writeln('      url: url,');
    buf.writeln('      headers: headers,');
    if (bodyVarName != null) {
      buf.writeln('      body: $bodyVarName,');
    }
    buf.writeln('    );');
    buf.writeln();
    buf.writeln('    final response = await _chain.send(request);');

    // Handle response
    if (hasTypedResponse) {
      _writeResponseDeserialization(buf, jsonSchema!);
    } else {
      buf.writeln('    return response;');
    }

    buf.writeln('  }');
  }

  List<String> _buildMethodParams(ApiOperation operation) {
    final params = <String>[];

    // Parameters (path, query, header)
    for (final param in operation.parameters) {
      final dartType = parameterSerializer.paramDartType(param);
      final fieldName = NameResolver.resolveFieldName(param.name);
      final requiredStr = param.required_ ? 'required ' : '';
      final deprecatedStr =
          param.deprecated ? "@Deprecated('Deprecated in API spec') " : '';
      params.add('$deprecatedStr$requiredStr$dartType $fieldName');
    }

    // Request body
    if (operation.requestBody != null) {
      final body = operation.requestBody!;
      final bodySchema = body.jsonSchema;
      if (bodySchema != null) {
        final dartType = _schemaToDartType(bodySchema);
        final requiredStr = body.required_ ? 'required ' : '';
        final nullSuffix = body.required_ ? '' : '?';
        params.add('$requiredStr$dartType$nullSuffix body');
      } else {
        // Non-JSON body — accept raw string
        final requiredStr = body.required_ ? 'required ' : '';
        final nullSuffix = body.required_ ? '' : '?';
        params.add('${requiredStr}String$nullSuffix body');
        diagnostics.add(Diagnostic(
          message: 'Operation "${operation.operationId}" has no JSON request '
              'content type. Accepting raw String body.',
          severity: DiagnosticSeverity.warning,
        ));
      }
    }

    return params;
  }

  void _writeUrlConstruction(
    StringBuffer buf,
    String pathTemplate,
    ApiOperation operation,
  ) {
    final pathParams =
        operation.parameters.where((p) => p.location == ParameterLocation.path);
    final queryParams = operation.parameters
        .where((p) => p.location == ParameterLocation.query);

    // Build path string with parameter interpolation
    var pathExpr = pathTemplate;
    for (final param in pathParams) {
      final encoded = parameterSerializer.pathParamExpression(param);
      pathExpr = pathExpr.replaceAll('{${param.name}}', '\${$encoded}');
    }

    // Normalize base URL: strip trailing slash
    buf.writeln(
        "    final basePath = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;");

    // Ensure path starts with /
    if (!pathExpr.startsWith('/')) {
      pathExpr = '/$pathExpr';
    }

    if (queryParams.isEmpty) {
      buf.writeln("    final url = Uri.parse('\$basePath$pathExpr');");
    } else {
      buf.writeln(
          '    final queryParams = <String, List<String>>{};');
      for (final param in queryParams) {
        buf.write(parameterSerializer.queryParamStatements(param));
      }
      buf.writeln(
          "    final url = Uri.parse('\$basePath$pathExpr').replace(");
      buf.writeln(
          '      queryParameters: queryParams,');
      buf.writeln('    );');
    }
  }

  void _writeHeaderConstruction(
    StringBuffer buf,
    ApiOperation operation,
  ) {
    final headerParams = operation.parameters
        .where((p) => p.location == ParameterLocation.header);
    final hasBody = operation.requestBody?.jsonSchema != null;

    buf.writeln('    final headers = <String, String>{');
    if (hasBody) {
      buf.writeln("      'Content-Type': 'application/json',");
    }
    for (final param in headerParams) {
      final fieldName = NameResolver.resolveFieldName(param.name);
      if (param.required_) {
        buf.writeln(
            "      '${param.name}': $fieldName.toString(),");
      }
    }
    buf.writeln('    };');

    // Add optional header params
    for (final param in headerParams) {
      if (!param.required_) {
        final fieldName = NameResolver.resolveFieldName(param.name);
        buf.writeln(
            "    if ($fieldName != null) { headers['${param.name}'] = $fieldName.toString(); }");
      }
    }
  }

  /// Returns the variable name for the serialized body, or null if no body.
  String? _writeBodySerialization(
    StringBuffer buf,
    ApiOperation operation,
  ) {
    if (operation.requestBody == null) return null;

    final body = operation.requestBody!;
    final jsonSchema = body.jsonSchema;

    if (jsonSchema != null) {
      // JSON body serialization → jsonBody variable
      if (body.required_) {
        if (_needsToJson(jsonSchema)) {
          buf.writeln(
              "    final jsonBody = jsonEncode(body.toJson());");
        } else {
          buf.writeln("    final jsonBody = jsonEncode(body);");
        }
      } else {
        if (_needsToJson(jsonSchema)) {
          buf.writeln(
              "    final jsonBody = body != null ? jsonEncode(body.toJson()) : null;");
        } else {
          buf.writeln(
              "    final jsonBody = body != null ? jsonEncode(body) : null;");
        }
      }
      return 'jsonBody';
    }

    // Non-JSON body — use the raw `body` parameter directly
    return 'body';
  }

  void _writeResponseDeserialization(
    StringBuffer buf,
    ApiSchema jsonSchema,
  ) {
    buf.writeln('    if (response.statusCode >= 200 && response.statusCode < 300) {');
    buf.writeln('      if (response.body.isEmpty) {');
    buf.writeln('        throw ApiException(');
    buf.writeln('          statusCode: response.statusCode,');
    buf.writeln("          body: 'Empty response body',");
    buf.writeln('          headers: response.headers,');
    buf.writeln('        );');
    buf.writeln('      }');
    buf.writeln(
        '      final json = jsonDecode(response.body);');

    final fromJsonExpr = _fromJsonExpression('json', jsonSchema);
    buf.writeln('      return ApiResponse(');
    buf.writeln('        data: $fromJsonExpr,');
    buf.writeln('        statusCode: response.statusCode,');
    buf.writeln('        headers: response.headers,');
    buf.writeln('      );');
    buf.writeln('    }');
    buf.writeln('    throw ApiException(');
    buf.writeln('      statusCode: response.statusCode,');
    buf.writeln('      body: response.body,');
    buf.writeln('      headers: response.headers,');
    buf.writeln('    );');
  }

  String _schemaToDartType(ApiSchema schema) {
    if (schema.isCircularRef && schema.refTarget != null) {
      return nameResolver.resolveClassName(schema.refTarget!);
    }
    if (schema.name != null && !schema.isPrimitive && !schema.isArray) {
      return nameResolver.resolveClassName(schema.name!);
    }
    if (schema.isFreeFormObject) {
      return 'Map<String, dynamic>';
    }
    if (schema.isEnum && schema.name != null) {
      return nameResolver.resolveClassName(schema.name!);
    }
    return switch (schema.type) {
      SchemaType.string => 'String',
      SchemaType.integer => 'int',
      SchemaType.number => 'double',
      SchemaType.boolean => 'bool',
      SchemaType.array => schema.items != null
          ? 'List<${_schemaToDartType(schema.items!)}>'
          : 'List<dynamic>',
      SchemaType.object =>
        schema.name != null
            ? nameResolver.resolveClassName(schema.name!)
            : 'Map<String, dynamic>',
      _ => 'dynamic',
    };
  }

  String _fromJsonExpression(String accessor, ApiSchema schema) {
    if (schema.isFreeFormObject) {
      return 'Map<String, dynamic>.from($accessor as Map)';
    }
    if (schema.isCircularRef && schema.refTarget != null) {
      final className = nameResolver.resolveClassName(schema.refTarget!);
      return '$className.fromJson($accessor as Map<String, dynamic>)';
    }
    if (schema.isEnum && schema.name != null) {
      final enumName = nameResolver.resolveClassName(schema.name!);
      return '$enumName.fromJson($accessor as String)';
    }
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      final className = nameResolver.resolveClassName(schema.name!);
      return '$className.fromJson($accessor as Map<String, dynamic>)';
    }
    return switch (schema.type) {
      SchemaType.string => '$accessor as String',
      SchemaType.integer => '($accessor as num).toInt()',
      SchemaType.number => '($accessor as num).toDouble()',
      SchemaType.boolean => '$accessor as bool',
      SchemaType.array => schema.items != null
          ? '($accessor as List<dynamic>).map((e) => ${_fromJsonExpression('e', schema.items!)}).toList()'
          : '$accessor as List<dynamic>',
      SchemaType.object =>
        schema.name != null
            ? '${nameResolver.resolveClassName(schema.name!)}.fromJson($accessor as Map<String, dynamic>)'
            : 'Map<String, dynamic>.from($accessor as Map)',
      _ => accessor,
    };
  }

  bool _needsToJson(ApiSchema schema) {
    if (schema.isEnum && schema.name != null) return true;
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      return true;
    }
    return false;
  }

  String _deriveClientName(String apiTitle) {
    final camel = _upperCamelCase(apiTitle);
    if (camel.endsWith('Client')) return camel;
    if (camel.endsWith('Api') || camel.endsWith('API')) return '${camel}Client';
    return '${camel}Client';
  }

  static String _upperCamelCase(String input) {
    // Replace non-alphanumeric with space, then split on camelCase boundaries
    final normalized = input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ');
    final withBoundaries = normalized.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final words =
        withBoundaries.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
  }
}

class _OperationWithPath {
  const _OperationWithPath(this.pathTemplate, this.operation);
  final String pathTemplate;
  final ApiOperation operation;
}
