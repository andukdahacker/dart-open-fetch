import '../ir/api_schema.dart';

/// Pre-processing pass that assigns synthetic names to unnamed inline
/// object schemas and inline enum schemas so that code generation
/// produces typed classes/enums instead of `Map<String, dynamic>` / `String`.
class InlineSchemaResolver {
  /// Schemas generated during resolution (new top-level models/enums).
  final List<ApiSchema> generatedSchemas = [];

  /// Track generated names to avoid collisions.
  final Set<String> _usedNames = {};

  /// Walk all schemas and resolve unnamed inline objects and enums.
  ///
  /// Returns the input schemas with property schemas replaced by named
  /// references. Newly created schemas are available in [generatedSchemas].
  List<ApiSchema> resolve(List<ApiSchema> schemas) {
    // Seed used names from existing named schemas.
    for (final schema in schemas) {
      if (schema.name != null) {
        _usedNames.add(schema.name!);
      }
    }

    return schemas.map((schema) {
      if (schema.name == null) return schema;
      return _resolveSchema(schema, schema.name!);
    }).toList();
  }

  ApiSchema _resolveSchema(ApiSchema schema, String parentName) {
    if (schema.properties.isEmpty && schema.items == null) {
      return schema;
    }

    final resolvedProperties = <ApiProperty>[];
    var changed = false;

    for (final prop in schema.properties) {
      final resolved = _resolveProperty(prop, parentName);
      resolvedProperties.add(resolved);
      if (!identical(resolved, prop)) changed = true;
    }

    // Resolve array items at the top level
    ApiSchema? resolvedItems = schema.items;
    if (schema.items != null) {
      resolvedItems = _resolveItemsSchema(schema.items!, parentName, null);
      if (!identical(resolvedItems, schema.items)) changed = true;
    }

    if (!changed) return schema;

    return schema.copyWith(
      properties: resolvedProperties,
      items: resolvedItems,
    );
  }

  ApiProperty _resolveProperty(ApiProperty prop, String parentName) {
    final schema = prop.schema;

    // Unnamed inline object with properties → create named class
    if (_isUnnamedInlineObject(schema)) {
      final name = _generateName(parentName, prop.name);
      final namedSchema = _resolveSchema(
        schema.copyWith(name: name),
        name,
      );
      generatedSchemas.add(namedSchema);
      return prop.copyWith(schema: namedSchema);
    }

    // Unnamed inline enum → create named enum
    if (_isUnnamedInlineEnum(schema)) {
      final name = _generateName(parentName, prop.name);
      final namedSchema = schema.copyWith(name: name);
      generatedSchemas.add(namedSchema);
      return prop.copyWith(schema: namedSchema);
    }

    // Array with unnamed inline items
    if (schema.isArray && schema.items != null) {
      final resolvedItems =
          _resolveItemsSchema(schema.items!, parentName, prop.name);
      if (!identical(resolvedItems, schema.items)) {
        return prop.copyWith(
          schema: schema.copyWith(items: resolvedItems),
        );
      }
    }

    // Named object that itself has inline properties → recurse
    if (schema.name != null && schema.properties.isNotEmpty) {
      final resolved = _resolveSchema(schema, schema.name!);
      if (!identical(resolved, schema)) {
        return prop.copyWith(schema: resolved);
      }
    }

    return prop;
  }

  /// Resolve array item schemas, assigning names to unnamed inline
  /// objects/enums found in item position.
  ApiSchema _resolveItemsSchema(
    ApiSchema items,
    String parentName,
    String? propertyName,
  ) {
    if (_isUnnamedInlineObject(items)) {
      final name = _generateName(
          parentName, propertyName != null ? '${propertyName}Item' : 'Item');
      final namedSchema = _resolveSchema(
        items.copyWith(name: name),
        name,
      );
      generatedSchemas.add(namedSchema);
      return namedSchema;
    }

    if (_isUnnamedInlineEnum(items)) {
      final name = _generateName(
          parentName, propertyName != null ? '${propertyName}Item' : 'Item');
      final namedSchema = items.copyWith(name: name);
      generatedSchemas.add(namedSchema);
      return namedSchema;
    }

    // Nested array (e.g. List<List<InlineObject>>)
    if (items.isArray && items.items != null) {
      final resolvedInner =
          _resolveItemsSchema(items.items!, parentName, propertyName);
      if (!identical(resolvedInner, items.items)) {
        return items.copyWith(items: resolvedInner);
      }
    }

    return items;
  }

  bool _isUnnamedInlineObject(ApiSchema schema) {
    return schema.name == null &&
        schema.type == SchemaType.object &&
        schema.properties.isNotEmpty;
  }

  bool _isUnnamedInlineEnum(ApiSchema schema) {
    return schema.name == null && schema.isEnum && !schema.isPrimitive ||
        (schema.name == null &&
            schema.isEnum &&
            schema.type == SchemaType.string);
  }

  String _generateName(String parentName, String propertyName) {
    // Convert propertyName to PascalCase
    final pascalProp = _toPascalCase(propertyName);
    final pascalParent = _toPascalCase(parentName);
    var candidate = '$pascalParent$pascalProp';

    if (_usedNames.contains(candidate)) {
      var suffix = 2;
      while (_usedNames.contains('$candidate$suffix')) {
        suffix++;
      }
      candidate = '$candidate$suffix';
    }

    _usedNames.add(candidate);
    return candidate;
  }

  static String _toPascalCase(String input) {
    return input
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join();
  }
}
