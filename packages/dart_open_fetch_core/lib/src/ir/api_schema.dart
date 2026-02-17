import 'package:collection/collection.dart';

/// The type system IR — represents all OpenAPI schema types.
class ApiSchema {
  ApiSchema({
    this.name,
    required this.type,
    this.format,
    this.description,
    this.properties = const [],
    this.requiredProperties = const {},
    this.items,
    this.additionalProperties,
    this.hasAdditionalProperties = false,
    this.enumValues,
    this.allOf = const [],
    this.oneOf = const [],
    this.anyOf = const [],
    this.discriminator,
    this.nullable = false,
    this.defaultValue,
    this.deprecated = false,
    this.isCircularRef = false,
    this.refTarget,
    this.schemaPath,
  });

  /// Schema name (from components/schemas key or inline generation).
  final String? name;

  /// The schema type: string, integer, number, boolean, array, object, or null for composed types.
  final SchemaType type;

  /// Format hint: date-time, uuid, email, uri, int32, int64, float, double, etc.
  final String? format;

  /// Description from the schema.
  final String? description;

  /// Named properties for object types.
  final List<ApiProperty> properties;

  /// Set of required property names.
  final Set<String> requiredProperties;

  /// Item schema for array types.
  final ApiSchema? items;

  /// Schema for additionalProperties values (Map value type).
  /// null means no additional properties constraint specified.
  final ApiSchema? additionalProperties;

  /// Whether additionalProperties is explicitly set (true = `Map<String, dynamic>`, schema = `Map<String, T>`).
  final bool hasAdditionalProperties;

  /// Enum raw string values.
  final List<String>? enumValues;

  /// allOf member schemas (flattened during parsing).
  final List<ApiSchema> allOf;

  /// oneOf variant schemas.
  final List<ApiSchema> oneOf;

  /// anyOf variant schemas.
  final List<ApiSchema> anyOf;

  /// Discriminator for oneOf/anyOf.
  final ApiDiscriminator? discriminator;

  /// Whether this schema is nullable.
  final bool nullable;

  /// Default value (as raw dynamic from JSON/YAML).
  final Object? defaultValue;

  /// Whether this schema is deprecated.
  final bool deprecated;

  /// Whether this is a placeholder for a circular $ref.
  final bool isCircularRef;

  /// Target schema name for circular refs (resolved in back-fill pass).
  final String? refTarget;

  /// JSON pointer path in source schema (for error reporting).
  final String? schemaPath;

  bool get isObject => type == SchemaType.object;
  bool get isArray => type == SchemaType.array;
  bool get isPrimitive =>
      type == SchemaType.string ||
      type == SchemaType.integer ||
      type == SchemaType.number ||
      type == SchemaType.boolean;
  bool get isEnum => enumValues != null && enumValues!.isNotEmpty;
  bool get isComposed => oneOf.isNotEmpty || anyOf.isNotEmpty;
  bool get isFreeFormObject =>
      isObject && properties.isEmpty && !hasAdditionalProperties;
  bool get hasNamedAndAdditionalProperties =>
      isObject && properties.isNotEmpty && hasAdditionalProperties;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiSchema &&
          name == other.name &&
          type == other.type &&
          format == other.format &&
          nullable == other.nullable &&
          isCircularRef == other.isCircularRef;

  @override
  int get hashCode => Object.hash(name, type, format, nullable, isCircularRef);

  @override
  String toString() => 'ApiSchema($name, $type${nullable ? '?' : ''})';
}

/// A named property within an object schema.
class ApiProperty {
  const ApiProperty({
    required this.name,
    required this.schema,
    this.description,
    this.deprecated = false,
  });

  final String name;
  final ApiSchema schema;
  final String? description;
  final bool deprecated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiProperty && name == other.name && schema == other.schema;

  @override
  int get hashCode => Object.hash(name, schema);

  @override
  String toString() => 'ApiProperty($name)';
}

/// Discriminator for oneOf/anyOf dispatch.
class ApiDiscriminator {
  const ApiDiscriminator({
    required this.propertyName,
    this.mapping = const {},
  });

  /// The property name used to discriminate.
  final String propertyName;

  /// Maps discriminator values to schema names.
  final Map<String, String> mapping;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiDiscriminator &&
          propertyName == other.propertyName &&
          const MapEquality<String, String>().equals(mapping, other.mapping);

  @override
  int get hashCode => Object.hash(
      propertyName, const MapEquality<String, String>().hash(mapping));

  @override
  String toString() => 'ApiDiscriminator($propertyName)';
}

/// Schema type enum.
enum SchemaType {
  string,
  integer,
  number,
  boolean,
  array,
  object,

  /// Used for composed types (oneOf/anyOf/allOf) that don't have a base type.
  composed,

  /// Dynamic / unknown type.
  dynamic_,
}
