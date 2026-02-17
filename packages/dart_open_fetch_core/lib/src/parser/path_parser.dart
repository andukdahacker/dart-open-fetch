import '../diagnostic.dart';
import '../ir/api_operation.dart';
import '../ir/api_parameter.dart';
import '../ir/api_path.dart';
import '../ir/api_request_body.dart';
import '../ir/api_response.dart';
import '../ir/api_schema.dart';
import 'schema_parser.dart';

/// Parses `paths` into [ApiPath] and [ApiOperation] IR nodes.
class PathParser {
  PathParser({required this.schemaParser});

  final SchemaParser schemaParser;
  final List<Diagnostic> diagnostics = [];

  static const _httpMethods = {
    'get',
    'post',
    'put',
    'delete',
    'patch',
    'head',
    'options',
  };

  /// Parse all paths from the schema.
  List<ApiPath> parsePaths(Map<String, dynamic> schema) {
    final paths = schema['paths'] as Map<String, dynamic>?;
    if (paths == null) return [];

    return paths.entries.map((entry) {
      final pathTemplate = entry.key;
      final pathNode = entry.value as Map<String, dynamic>;
      return _parsePath(pathTemplate, pathNode);
    }).toList();
  }

  ApiPath _parsePath(String pathTemplate, Map<String, dynamic> node) {
    // Path-level parameters (shared by all operations on this path)
    final pathLevelParams = _parseParameters(
      node['parameters'] as List?,
      '#/paths/${_encodeJsonPointer(pathTemplate)}/parameters',
    );

    final operations = <ApiOperation>[];
    for (final method in _httpMethods) {
      if (node.containsKey(method)) {
        final opNode = node[method] as Map<String, dynamic>;
        final basePath = '#/paths/${_encodeJsonPointer(pathTemplate)}/$method';
        operations.add(
          _parseOperation(
              method, opNode, pathLevelParams, basePath, pathTemplate),
        );
      }
    }

    return ApiPath(path: pathTemplate, operations: operations);
  }

  ApiOperation _parseOperation(
    String method,
    Map<String, dynamic> node,
    List<ApiParameter> pathLevelParams,
    String basePath,
    String pathTemplate,
  ) {
    // Merge path-level and operation-level params (operation overrides path)
    final opParams = _parseParameters(
      node['parameters'] as List?,
      '$basePath/parameters',
    );
    final mergedParams = _mergeParameters(pathLevelParams, opParams);

    // operationId
    var operationId = node['operationId'] as String?;
    if (operationId == null || operationId.isEmpty) {
      operationId = _generateOperationId(method, pathTemplate);
    }

    // Request body
    ApiRequestBody? requestBody;
    if (node.containsKey('requestBody')) {
      requestBody = _parseRequestBody(
        node['requestBody'] as Map<String, dynamic>,
        '$basePath/requestBody',
      );
    }

    // Responses
    final responses = <ApiResponse>[];
    if (node.containsKey('responses')) {
      final responsesNode = node['responses'] as Map<String, dynamic>;
      for (final entry in responsesNode.entries) {
        responses.add(_parseResponse(
          entry.key,
          entry.value as Map<String, dynamic>,
          '$basePath/responses/${entry.key}',
        ));
      }
    }

    // Security
    final security = <Map<String, List<String>>>[];
    if (node.containsKey('security')) {
      final secList = node['security'] as List;
      for (final item in secList) {
        final secMap = <String, List<String>>{};
        final rawMap = item as Map<String, dynamic>;
        for (final entry in rawMap.entries) {
          secMap[entry.key] = (entry.value as List).cast<String>();
        }
        security.add(secMap);
      }
    }

    // Tags
    final tags = <String>[];
    if (node.containsKey('tags')) {
      tags.addAll((node['tags'] as List).cast<String>());
    }

    return ApiOperation(
      method: method,
      operationId: operationId,
      summary: node['summary'] as String?,
      description: node['description'] as String?,
      parameters: mergedParams,
      requestBody: requestBody,
      responses: responses,
      security: security,
      tags: tags,
      deprecated: node['deprecated'] == true,
    );
  }

  List<ApiParameter> _parseParameters(List? paramList, String basePath) {
    if (paramList == null) return [];
    return paramList.asMap().entries.map((entry) {
      final node = entry.value as Map<String, dynamic>;
      return _parseParameter(node, '$basePath/${entry.key}');
    }).toList();
  }

  ApiParameter _parseParameter(Map<String, dynamic> node, String path) {
    final location = _parseLocation(node['in'] as String);
    final style = node['style'] as String?;
    final explode = node['explode'] as bool?;

    // Warn about unsupported styles
    if (style != null) {
      final isDefault =
          (location == ParameterLocation.path && style == 'simple') ||
              ((location == ParameterLocation.query ||
                      location == ParameterLocation.cookie) &&
                  style == 'form');
      if (!isDefault) {
        diagnostics.add(Diagnostic(
          message: 'Unsupported parameter style "$style" for ${node['name']}, '
              'using default serialization',
          schemaPath: path,
          severity: DiagnosticSeverity.warning,
        ));
      }
    }

    ApiSchema paramSchema;
    if (node.containsKey('schema')) {
      paramSchema = schemaParser.parseSchema(
        node['schema'] as Map<String, dynamic>,
        path: '$path/schema',
      );
    } else {
      paramSchema = ApiSchema(name: null, type: SchemaType.string);
    }

    return ApiParameter(
      name: node['name'] as String,
      location: location,
      schema: paramSchema,
      required_: node['required'] == true,
      description: node['description'] as String?,
      style: style,
      explode: explode,
      deprecated: node['deprecated'] == true,
    );
  }

  ParameterLocation _parseLocation(String location) {
    switch (location) {
      case 'query':
        return ParameterLocation.query;
      case 'path':
        return ParameterLocation.path;
      case 'header':
        return ParameterLocation.header;
      case 'cookie':
        return ParameterLocation.cookie;
      default:
        return ParameterLocation.query;
    }
  }

  ApiRequestBody _parseRequestBody(
    Map<String, dynamic> node,
    String path,
  ) {
    final content = <String, ApiSchema>{};
    if (node.containsKey('content')) {
      final contentNode = node['content'] as Map<String, dynamic>;
      for (final entry in contentNode.entries) {
        final mediaType = entry.value as Map<String, dynamic>;
        if (mediaType.containsKey('schema')) {
          content[entry.key] = schemaParser.parseSchema(
            mediaType['schema'] as Map<String, dynamic>,
            path: '$path/content/${entry.key}/schema',
          );
        }
      }
    }

    return ApiRequestBody(
      required_: node['required'] == true,
      content: content,
      description: node['description'] as String?,
    );
  }

  ApiResponse _parseResponse(
    String statusCode,
    Map<String, dynamic> node,
    String path,
  ) {
    final content = <String, ApiSchema>{};
    if (node.containsKey('content')) {
      final contentNode = node['content'] as Map<String, dynamic>;
      for (final entry in contentNode.entries) {
        final mediaType = entry.value as Map<String, dynamic>;
        if (mediaType.containsKey('schema')) {
          content[entry.key] = schemaParser.parseSchema(
            mediaType['schema'] as Map<String, dynamic>,
            path: '$path/content/${entry.key}/schema',
          );
        }
      }
    }

    final headers = <String, ApiSchema>{};
    if (node.containsKey('headers')) {
      final headersNode = node['headers'] as Map<String, dynamic>;
      for (final entry in headersNode.entries) {
        final headerNode = entry.value as Map<String, dynamic>;
        if (headerNode.containsKey('schema')) {
          headers[entry.key] = schemaParser.parseSchema(
            headerNode['schema'] as Map<String, dynamic>,
            path: '$path/headers/${entry.key}/schema',
          );
        }
      }
    }

    return ApiResponse(
      statusCode: statusCode,
      description: node['description'] as String?,
      content: content,
      headers: headers,
    );
  }

  /// Merge path-level and operation-level params.
  /// Operation-level overrides path-level for same name+location.
  List<ApiParameter> _mergeParameters(
    List<ApiParameter> pathLevel,
    List<ApiParameter> opLevel,
  ) {
    final merged = <String, ApiParameter>{};
    for (final p in pathLevel) {
      merged['${p.location}:${p.name}'] = p;
    }
    for (final p in opLevel) {
      merged['${p.location}:${p.name}'] = p;
    }
    return merged.values.toList();
  }

  /// Generate operationId from method + path.
  String _generateOperationId(String method, String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).map((s) {
      if (s.startsWith('{') && s.endsWith('}')) {
        final param = s.substring(1, s.length - 1);
        return 'By${_capitalize(param)}';
      }
      return _capitalize(s);
    }).join();
    return '${method.toLowerCase()}$parts';
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _encodeJsonPointer(String segment) {
    return segment.replaceAll('~', '~0').replaceAll('/', '~1');
  }
}
