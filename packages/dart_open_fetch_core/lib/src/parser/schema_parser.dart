import '../diagnostic.dart';
import '../ir/api_schema.dart';
import 'ref_resolver.dart' show circularRefMarker, refTargetMarker;

/// Parses `components/schemas` into [ApiSchema] IR nodes.
///
/// Uses a pointer-sharing registry: each component schema is parsed exactly
/// once into [ApiSchema] and the same instance is returned for every `$ref`
/// that targets it. This avoids the deep-copy memory explosion that occurs
/// when large specs (GitHub 8.6MB, Stripe 5.8MB) are fully inlined.
class SchemaParser {
  final List<Diagnostic> diagnostics = [];

  /// Raw component schema maps (pointers into rootSchema, zero copy).
  final Map<String, Map<String, dynamic>> _rawSchemas = {};

  /// Parsed schema registry. Each component schema is parsed at most once.
  final Map<String, ApiSchema> _schemaCache = {};

  /// Schema names currently being parsed (for circular detection).
  final Set<String> _parsing = {};

  /// Shared circular-ref stubs so all back-references to the same schema
  /// return the same instance.
  final Map<String, ApiSchema> _circularStubs = {};

  /// Parse all named schemas from the components section.
  ///
  /// Builds the schema registry fresh on each call. Subsequent calls to
  /// [parseSchema] that encounter `$ref` nodes resolve via the registry.
  List<ApiSchema> parseComponents(Map<String, dynamic> schema) {
    // Clear previous state so this method is safe to call more than once.
    _rawSchemas.clear();
    _schemaCache.clear();
    _circularStubs.clear();

    final components = schema['components'] as Map<String, dynamic>?;
    if (components == null) return [];

    final schemas = components['schemas'] as Map<String, dynamic>?;
    if (schemas == null) return [];

    // Store raw schemas for on-demand parsing via the registry.
    for (final entry in schemas.entries) {
      _rawSchemas[entry.key] = entry.value as Map<String, dynamic>;
    }

    // Parse each component schema through the cache.
    return schemas.keys.map((name) => _parseComponentSchema(name)).toList();
  }

  /// Parse a component schema by name, using cache for deduplication.
  ApiSchema _parseComponentSchema(String name) {
    // Return cached result if already parsed.
    if (_schemaCache.containsKey(name)) {
      return _schemaCache[name]!;
    }

    // Circular detection: if we're already parsing this schema,
    // return a shared stub that code generation resolves by name.
    if (_parsing.contains(name)) {
      return _circularStubs.putIfAbsent(
        name,
        () => ApiSchema(
          name: name,
          type: SchemaType.object,
          isCircularRef: true,
          refTarget: name,
          schemaPath: '#/components/schemas/$name',
        ),
      );
    }

    final raw = _rawSchemas[name];
    if (raw == null) {
      diagnostics.add(Diagnostic(
        message: 'Referenced component schema "$name" not found',
        schemaPath: '#/components/schemas/$name',
        severity: DiagnosticSeverity.warning,
      ));
      return ApiSchema(
        name: name,
        type: SchemaType.dynamic_,
        schemaPath: '#/components/schemas/$name',
      );
    }

    _parsing.add(name);
    try {
      final result = parseSchema(
        raw,
        name: name,
        path: '#/components/schemas/$name',
      );
      _schemaCache[name] = result;
      return result;
    } catch (e) {
      // Cache a dynamic fallback so we don't retry on subsequent references.
      final fallback = ApiSchema(
        name: name,
        type: SchemaType.dynamic_,
        schemaPath: '#/components/schemas/$name',
      );
      _schemaCache[name] = fallback;
      diagnostics.add(Diagnostic(
        message: 'Failed to parse component schema "$name": $e',
        schemaPath: '#/components/schemas/$name',
        severity: DiagnosticSeverity.warning,
      ));
      return fallback;
    } finally {
      _parsing.remove(name);
    }
  }

  /// Parse a single schema node into an [ApiSchema].
  ///
  /// When encountering a `$ref` to a component schema, resolves it via the
  /// registry (returning the shared cached instance) instead of requiring
  /// the caller to have inlined the target.
  ApiSchema parseSchema(
    Map<String, dynamic> node, {
    String? name,
    String? path,
  }) {
    // Handle unresolved component schema $ref (left by RefResolver).
    if (node.containsKey(r'$ref')) {
      final ref = node[r'$ref'] as String;
      if (ref.startsWith('#/components/schemas/')) {
        final targetName = ref.substring('#/components/schemas/'.length);
        final resolved = _parseComponentSchema(targetName);
        if (name != null && name != targetName && name != resolved.name) {
          diagnostics.add(Diagnostic(
            message: '\$ref resolved "$name" to "${resolved.name}" '
                '— caller name discarded per \$ref semantics',
            schemaPath: path,
            severity: DiagnosticSeverity.info,
          ));
        }
        return resolved;
      }
      // Non-schema $ref should have been resolved by RefResolver.
      diagnostics.add(Diagnostic(
        message: 'Unresolved \$ref: $ref',
        schemaPath: path,
        severity: DiagnosticSeverity.warning,
      ));
      return ApiSchema(
        name: name,
        type: SchemaType.dynamic_,
        schemaPath: path,
      );
    }

    // Handle circular ref markers from the resolver (non-schema refs only)
    if (node[circularRefMarker] == true) {
      return ApiSchema(
        name: name,
        type: SchemaType.object,
        isCircularRef: true,
        refTarget: node[refTargetMarker] as String?,
        schemaPath: path,
      );
    }

    // Handle allOf (flatten)
    if (node.containsKey('allOf')) {
      return _parseAllOf(node, name: name, path: path);
    }

    // Handle oneOf
    if (node.containsKey('oneOf')) {
      return _parseOneOf(node, name: name, path: path);
    }

    // Handle anyOf
    if (node.containsKey('anyOf')) {
      return _parseAnyOf(node, name: name, path: path);
    }

    final type = _parseType(node);
    final nullable = node['nullable'] == true;
    final deprecated = node['deprecated'] == true;
    final format = node['format'] as String?;
    final description = node['description'] as String?;
    final defaultValue = node['default'];

    // Enum values
    List<String>? enumValues;
    if (node.containsKey('enum')) {
      final raw = node['enum'] as List;
      enumValues = raw.map((e) => e?.toString() ?? '').toList();
    }

    // Array items
    ApiSchema? items;
    if (type == SchemaType.array && node.containsKey('items')) {
      items = parseSchema(
        node['items'] as Map<String, dynamic>,
        path: path != null ? '$path/items' : null,
      );
    }

    // Object properties
    List<ApiProperty> properties = [];
    Set<String> requiredProperties = {};
    ApiSchema? additionalPropsSchema;
    bool hasAdditionalProperties = false;

    if (type == SchemaType.object) {
      if (node.containsKey('required')) {
        requiredProperties =
            (node['required'] as List).cast<String>().toSet();
      }

      if (node.containsKey('properties')) {
        final props = node['properties'] as Map<String, dynamic>;
        properties = props.entries.map((entry) {
          final propSchema = parseSchema(
            entry.value as Map<String, dynamic>,
            path: path != null ? '$path/properties/${entry.key}' : null,
          );
          final propDeprecated =
              (entry.value as Map<String, dynamic>)['deprecated'] == true;
          return ApiProperty(
            name: entry.key,
            schema: propSchema,
            description:
                (entry.value as Map<String, dynamic>)['description'] as String?,
            deprecated: propDeprecated,
          );
        }).toList();
      }

      // additionalProperties handling
      if (node.containsKey('additionalProperties')) {
        final ap = node['additionalProperties'];
        hasAdditionalProperties = true;
        if (ap is Map<String, dynamic>) {
          additionalPropsSchema = parseSchema(
            ap,
            path:
                path != null ? '$path/additionalProperties' : null,
          );
        }
        // If ap is true or absent schema, additionalPropsSchema stays null
        // meaning Map<String, dynamic>
      }
    }

    return ApiSchema(
      name: name,
      type: type,
      format: format,
      description: description,
      properties: properties,
      requiredProperties: requiredProperties,
      items: items,
      additionalProperties: additionalPropsSchema,
      hasAdditionalProperties: hasAdditionalProperties,
      enumValues: enumValues,
      nullable: nullable,
      defaultValue: defaultValue,
      deprecated: deprecated,
      schemaPath: path,
    );
  }

  ApiSchema _parseAllOf(
    Map<String, dynamic> node, {
    String? name,
    String? path,
  }) {
    final allOfList = node['allOf'] as List;
    final mergedProperties = <String, ApiProperty>{};
    final mergedRequired = <String>{};

    for (var i = 0; i < allOfList.length; i++) {
      final member = allOfList[i] as Map<String, dynamic>;
      final memberSchema = parseSchema(
        member,
        path: path != null ? '$path/allOf/$i' : null,
      );

      for (final prop in memberSchema.properties) {
        if (mergedProperties.containsKey(prop.name)) {
          final existing = mergedProperties[prop.name]!;
          if (existing.schema.type != prop.schema.type) {
            // Type conflict → use dynamic
            mergedProperties[prop.name] = ApiProperty(
              name: prop.name,
              schema: ApiSchema(
                name: null,
                type: SchemaType.dynamic_,
                schemaPath: prop.schema.schemaPath,
              ),
              description: prop.description ?? existing.description,
            );
            diagnostics.add(Diagnostic(
              message:
                  'allOf type conflict for property "${prop.name}": '
                  '${existing.schema.type} vs ${prop.schema.type}, using dynamic',
              schemaPath: path,
              severity: DiagnosticSeverity.warning,
            ));
          }
          // Same type = deduplicate (keep existing)
        } else {
          mergedProperties[prop.name] = prop;
        }
      }

      mergedRequired.addAll(memberSchema.requiredProperties);
    }

    return ApiSchema(
      name: name,
      type: SchemaType.object,
      properties: mergedProperties.values.toList(),
      requiredProperties: mergedRequired,
      nullable: node['nullable'] == true,
      deprecated: node['deprecated'] == true,
      description: node['description'] as String?,
      schemaPath: path,
    );
  }

  ApiSchema _parseOneOf(
    Map<String, dynamic> node, {
    String? name,
    String? path,
  }) {
    final oneOfList = node['oneOf'] as List;
    final variants = <ApiSchema>[];

    for (var i = 0; i < oneOfList.length; i++) {
      final variant = oneOfList[i] as Map<String, dynamic>;
      variants.add(parseSchema(
        variant,
        path: path != null ? '$path/oneOf/$i' : null,
      ));
    }

    ApiDiscriminator? discriminator;
    if (node.containsKey('discriminator')) {
      final disc = node['discriminator'] as Map<String, dynamic>;
      final mapping = <String, String>{};
      if (disc.containsKey('mapping')) {
        final rawMapping = disc['mapping'] as Map<String, dynamic>;
        for (final entry in rawMapping.entries) {
          // Resolve $ref paths to schema names
          var target = entry.value as String;
          if (target.startsWith('#/components/schemas/')) {
            target = target.split('/').last;
          }
          mapping[entry.key] = target;
        }
      }
      discriminator = ApiDiscriminator(
        propertyName: disc['propertyName'] as String,
        mapping: mapping,
      );
    }

    return ApiSchema(
      name: name,
      type: SchemaType.composed,
      oneOf: variants,
      discriminator: discriminator,
      nullable: node['nullable'] == true,
      deprecated: node['deprecated'] == true,
      description: node['description'] as String?,
      schemaPath: path,
    );
  }

  ApiSchema _parseAnyOf(
    Map<String, dynamic> node, {
    String? name,
    String? path,
  }) {
    final anyOfList = node['anyOf'] as List;
    final variants = <ApiSchema>[];

    for (var i = 0; i < anyOfList.length; i++) {
      final variant = anyOfList[i] as Map<String, dynamic>;
      variants.add(parseSchema(
        variant,
        path: path != null ? '$path/anyOf/$i' : null,
      ));
    }

    return ApiSchema(
      name: name,
      type: SchemaType.composed,
      anyOf: variants,
      nullable: node['nullable'] == true,
      deprecated: node['deprecated'] == true,
      description: node['description'] as String?,
      schemaPath: path,
    );
  }

  SchemaType _parseType(Map<String, dynamic> node) {
    final type = node['type'] as String?;
    if (type == null) {
      // No explicit type — infer from structure
      if (node.containsKey('properties') ||
          node.containsKey('additionalProperties')) {
        return SchemaType.object;
      }
      if (node.containsKey('items')) return SchemaType.array;
      if (node.containsKey('enum')) return SchemaType.string;
      return SchemaType.object;
    }

    switch (type) {
      case 'string':
        return SchemaType.string;
      case 'integer':
        return SchemaType.integer;
      case 'number':
        return SchemaType.number;
      case 'boolean':
        return SchemaType.boolean;
      case 'array':
        return SchemaType.array;
      case 'object':
        return SchemaType.object;
      default:
        diagnostics.add(Diagnostic(
          message: 'Unrecognized schema type "$type", treating as object',
          severity: DiagnosticSeverity.warning,
        ));
        return SchemaType.object;
    }
  }
}
