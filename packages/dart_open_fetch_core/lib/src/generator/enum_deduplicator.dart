import '../ir/api_schema.dart';

/// Deduplicates enum schemas that share identical value sets.
///
/// Groups named enum schemas by their sorted values, picks the shortest
/// name as canonical, and rewrites all property references to use it.
class EnumDeduplicator {
  /// Deduplicate enum schemas in [schemas].
  ///
  /// Returns a new list with duplicate enums removed and all property
  /// references rewritten to point to the canonical enum name.
  List<ApiSchema> deduplicate(List<ApiSchema> schemas) {
    // Group enum schemas by sorted value set
    final enumGroups = <String, List<ApiSchema>>{};
    for (final schema in schemas) {
      if (!schema.isEnum || schema.name == null) continue;
      final key = _valueKey(schema.enumValues!);
      enumGroups.putIfAbsent(key, () => []).add(schema);
    }

    // Build rename map: old name → canonical name
    final renameMap = <String, String>{};
    final removedNames = <String>{};
    for (final group in enumGroups.values) {
      if (group.length <= 1) continue;
      // Pick shortest name as canonical
      group.sort((a, b) => a.name!.length.compareTo(b.name!.length));
      final canonical = group.first.name!;
      for (var i = 1; i < group.length; i++) {
        renameMap[group[i].name!] = canonical;
        removedNames.add(group[i].name!);
      }
    }

    if (renameMap.isEmpty) return schemas;

    // Remove duplicate schemas and rewrite references
    return schemas
        .where((s) => s.name == null || !removedNames.contains(s.name))
        .map((s) => _rewriteSchema(s, renameMap))
        .toList();
  }

  String _valueKey(List<String> values) {
    final sorted = List<String>.from(values)..sort();
    return sorted.join('\x00');
  }

  ApiSchema _rewriteSchema(ApiSchema schema, Map<String, String> renameMap) {
    var changed = false;

    // Rewrite properties
    final newProps = <ApiProperty>[];
    for (final prop in schema.properties) {
      final rewritten = _rewriteProperty(prop, renameMap);
      newProps.add(rewritten);
      if (!identical(rewritten, prop)) changed = true;
    }

    // Rewrite items
    ApiSchema? newItems = schema.items;
    if (schema.items != null) {
      newItems = _rewriteSchema(schema.items!, renameMap);
      if (!identical(newItems, schema.items)) changed = true;
    }

    // Rewrite additionalProperties
    ApiSchema? newAdditional = schema.additionalProperties;
    if (schema.additionalProperties != null) {
      newAdditional = _rewriteSchema(schema.additionalProperties!, renameMap);
      if (!identical(newAdditional, schema.additionalProperties)) {
        changed = true;
      }
    }

    // Rewrite oneOf/anyOf/allOf
    final newOneOf = _rewriteList(schema.oneOf, renameMap);
    if (!identical(newOneOf, schema.oneOf)) changed = true;
    final newAnyOf = _rewriteList(schema.anyOf, renameMap);
    if (!identical(newAnyOf, schema.anyOf)) changed = true;
    final newAllOf = _rewriteList(schema.allOf, renameMap);
    if (!identical(newAllOf, schema.allOf)) changed = true;

    if (!changed) return schema;

    return schema.copyWith(
      properties: newProps,
      items: newItems,
      additionalProperties: newAdditional,
      oneOf: newOneOf,
      anyOf: newAnyOf,
      allOf: newAllOf,
    );
  }

  List<ApiSchema> _rewriteList(
      List<ApiSchema> schemas, Map<String, String> renameMap) {
    var changed = false;
    final result = <ApiSchema>[];
    for (final s in schemas) {
      final rewritten = _rewriteSchema(s, renameMap);
      result.add(rewritten);
      if (!identical(rewritten, s)) changed = true;
    }
    return changed ? result : schemas;
  }

  ApiProperty _rewriteProperty(
      ApiProperty prop, Map<String, String> renameMap) {
    final schema = prop.schema;

    // Direct enum reference
    if (schema.isEnum &&
        schema.name != null &&
        renameMap.containsKey(schema.name)) {
      return prop.copyWith(
        schema: schema.copyWith(name: renameMap[schema.name]),
      );
    }

    // Recurse into schema
    final rewritten = _rewriteSchema(schema, renameMap);
    if (identical(rewritten, schema)) return prop;
    return prop.copyWith(schema: rewritten);
  }
}
