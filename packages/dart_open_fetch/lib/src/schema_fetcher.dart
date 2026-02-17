import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

/// Fetches and parses OpenAPI schemas from URLs or local files.
class SchemaFetcher {
  /// Load a schema from a URL or file path.
  ///
  /// Returns the parsed schema as a plain `Map<String, dynamic>` and the
  /// base directory path for resolving relative `$ref`s.
  Future<SchemaFetchResult> fetch(String schemaPath) async {
    final String content;
    final String basePath;

    if (schemaPath.startsWith('http://') || schemaPath.startsWith('https://')) {
      content = await _fetchUrl(schemaPath);
      basePath = Directory.current.path;
    } else {
      final file = File(schemaPath);
      if (!file.existsSync()) {
        throw SchemaFetchException('File not found: $schemaPath');
      }
      content = await file.readAsString();
      basePath = file.parent.path;
    }

    final schema = _parseContent(content);
    return SchemaFetchResult(schema: schema, basePath: basePath);
  }

  /// Create a [FileReader] callback for resolving relative `$ref`s.
  Future<Map<String, dynamic>> Function(String) fileReader(String basePath) {
    return (String relativePath) async {
      final file = File('$basePath/$relativePath');
      if (!file.existsSync()) {
        throw SchemaFetchException(
            'Referenced file not found: $relativePath (resolved to ${file.path})');
      }
      final content = await file.readAsString();
      return _parseContent(content);
    };
  }

  Future<String> _fetchUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw SchemaFetchException(
          'Failed to fetch schema from $url: HTTP ${response.statusCode}');
    }
    return response.body;
  }

  /// Parse content as JSON or YAML into a plain Map.
  Map<String, dynamic> _parseContent(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{')) {
      return Map<String, dynamic>.from(jsonDecode(content) as Map);
    }
    final yamlResult = loadYaml(content);
    return _deepConvert(yamlResult) as Map<String, dynamic>;
  }

  /// Deep-convert YamlMap/YamlList to plain Dart Map/List.
  static dynamic _deepConvert(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (e) => MapEntry<String, dynamic>(
              e.key.toString(), _deepConvert(e.value)),
        ),
      );
    }
    if (value is List) {
      return value.map(_deepConvert).toList();
    }
    return value;
  }
}

/// Result of fetching a schema.
class SchemaFetchResult {
  const SchemaFetchResult({
    required this.schema,
    required this.basePath,
  });

  final Map<String, dynamic> schema;
  final String basePath;
}

/// Exception thrown when schema fetching fails.
class SchemaFetchException implements Exception {
  SchemaFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}
