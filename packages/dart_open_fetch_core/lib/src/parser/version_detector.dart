/// Detects and normalizes OpenAPI version differences.
class VersionDetector {
  /// Detect the OpenAPI version from the schema.
  OpenApiVersion detect(Map<String, dynamic> schema) {
    final version = schema['openapi'] as String;
    if (version.startsWith('3.1')) return OpenApiVersion.v3_1;
    return OpenApiVersion.v3_0;
  }

  /// Normalize a schema in-place to unify 3.0 and 3.1 differences.
  /// After normalization, the parser deals with a single format internally.
  Map<String, dynamic> normalize(
    Map<String, dynamic> schema,
    OpenApiVersion version,
  ) {
    if (version == OpenApiVersion.v3_1) {
      _deepConvertAndNormalize(schema);
    }
    return schema;
  }

  /// Deeply convert all nested maps to `Map<String, dynamic>` and normalize.
  void _deepConvertAndNormalize(Map<String, dynamic> map) {
    // First pass: ensure all child values are properly typed Map<String, dynamic>
    final keys = map.keys.toList();
    for (final key in keys) {
      map[key] = _ensureDynamic(map[key]);
    }

    // Apply normalizations to this node
    _normalizeTypeArray(map);
    _normalizeExamples(map);

    // Recurse into children
    for (final key in map.keys) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        _deepConvertAndNormalize(value);
      } else if (value is List) {
        _deepConvertList(value);
      }
    }
  }

  void _deepConvertList(List list) {
    for (var i = 0; i < list.length; i++) {
      list[i] = _ensureDynamic(list[i]);
      final value = list[i];
      if (value is Map<String, dynamic>) {
        _deepConvertAndNormalize(value);
      } else if (value is List) {
        _deepConvertList(value);
      }
    }
  }

  /// Convert a value to use `Map<String, dynamic>` if it's a Map.
  dynamic _ensureDynamic(dynamic value) {
    if (value is Map && value is! Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map<String, dynamic>) {
      // Even if it passes the type check, the internal type parameter
      // might be narrower (e.g., Map<String, List<String>>).
      // Create a new map to ensure mutation works.
      return _safeConvertMap(value);
    }
    if (value is List) {
      return List<dynamic>.from(value.map(_ensureDynamic));
    }
    return value;
  }

  Map<String, dynamic> _safeConvertMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// 3.1: `type: [string, "null"]` → `type: string, nullable: true`
  /// 3.1: `type: [T1, T2]` → `oneOf: [{type: T1}, {type: T2}]`
  /// 3.1: `type: [T1, T2, "null"]` → `oneOf: [{type: T1}, {type: T2}], nullable: true`
  void _normalizeTypeArray(Map<String, dynamic> node) {
    final type = node['type'];
    if (type is! List) return;

    final types = List<String>.from(type);
    final hasNull = types.contains('null');
    final nonNullTypes = types.where((t) => t != 'null').toList();

    // Remove the array type first
    node.remove('type');

    if (hasNull) {
      node['nullable'] = true;
    }

    if (nonNullTypes.length == 1) {
      node['type'] = nonNullTypes.first;
    } else if (nonNullTypes.length > 1) {
      node['oneOf'] =
          nonNullTypes.map((t) => <String, dynamic>{'type': t}).toList();
    } else {
      node['type'] = 'object';
      node['nullable'] = true;
    }
  }

  /// 3.1: `examples: [...]` → keep `example` if it exists, else use first.
  void _normalizeExamples(Map<String, dynamic> node) {
    if (!node.containsKey('examples') || node.containsKey('example')) return;
    final examples = node['examples'];
    if (examples is List && examples.isNotEmpty) {
      node['example'] = examples.first;
    }
  }
}

enum OpenApiVersion { v3_0, v3_1 }
