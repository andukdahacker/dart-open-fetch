import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

import '../diagnostic.dart';
import '../ir/api_schema.dart';
import 'name_resolver.dart';

/// Generates sealed class hierarchies for oneOf/anyOf schemas.
class UnionGenerator {
  UnionGenerator({required this.nameResolver});

  final NameResolver nameResolver;
  final List<Diagnostic> diagnostics = [];

  /// Generate a Dart source string for a union (oneOf/anyOf) schema.
  ///
  /// Produces a sealed base class with a factory `fromJson` and one
  /// subclass per variant. The file contains the complete hierarchy.
  String generateUnion(ApiSchema schema) {
    final baseName = nameResolver.resolveClassName(schema.name!);
    final variants = schema.oneOf.isNotEmpty ? schema.oneOf : schema.anyOf;
    final hasDiscriminator = schema.discriminator != null;

    final buf = StringBuffer();

    // Sealed base class
    _writeSealedBase(
      buf,
      schema,
      baseName,
      variants,
      hasDiscriminator ? schema.discriminator : null,
    );

    // Variant subclasses
    for (final variant in variants) {
      buf.writeln();
      _writeVariantClass(buf, baseName, variant);
    }

    try {
      return DartFormatter(languageVersion: Version(3, 5, 0))
          .format(buf.toString());
    } catch (e) {
      diagnostics.add(Diagnostic(
        message: 'Failed to format union "${schema.name}": $e',
        severity: DiagnosticSeverity.warning,
      ));
      return buf.toString();
    }
  }

  void _writeSealedBase(
    StringBuffer buf,
    ApiSchema schema,
    String baseName,
    List<ApiSchema> variants,
    ApiDiscriminator? discriminator,
  ) {
    if (schema.deprecated) {
      buf.writeln("@Deprecated('Deprecated in API spec')");
    }

    buf.writeln('sealed class $baseName {');

    // Factory fromJson
    buf.writeln('  factory $baseName.fromJson(Map<String, dynamic> json) {');
    if (discriminator != null) {
      _writeDiscriminatorFromJson(buf, baseName, variants, discriminator);
    } else {
      _writeTryParseFromJson(buf, baseName, variants);
    }
    buf.writeln('  }');

    buf.writeln();

    // Abstract toJson
    buf.writeln('  Map<String, dynamic> toJson();');

    buf.writeln('}');
  }

  void _writeDiscriminatorFromJson(
    StringBuffer buf,
    String baseName,
    List<ApiSchema> variants,
    ApiDiscriminator discriminator,
  ) {
    final propName = discriminator.propertyName;
    buf.writeln("    final disc = json['$propName'] as String;");
    buf.writeln('    return switch (disc) {');

    for (final variant in variants) {
      final variantClassName = _variantClassName(baseName, variant);
      final variantType = _variantDartType(variant);

      // Look up discriminator value from mapping, fall back to schema name
      String discValue = variant.name ?? '';
      for (final entry in discriminator.mapping.entries) {
        final refName = entry.value.split('/').last;
        if (refName == variant.name) {
          discValue = entry.key;
          break;
        }
      }

      buf.writeln(
          "      '$discValue' => $variantClassName($variantType.fromJson(json)),");
    }

    buf.writeln(
      "      _ => throw FormatException("
      "'Unknown $baseName discriminator value: \$disc'),",
    );
    buf.writeln('    };');
  }

  void _writeTryParseFromJson(
    StringBuffer buf,
    String baseName,
    List<ApiSchema> variants,
  ) {
    final triedTypes = <String>[];

    for (final variant in variants) {
      final variantClassName = _variantClassName(baseName, variant);
      final variantType = _variantDartType(variant);
      triedTypes.add(variantType);

      buf.writeln('    try {');
      buf.writeln(
          '      return $variantClassName($variantType.fromJson(json));');
      buf.writeln('    } on FormatException {');
      buf.writeln('      // Try next variant');
      buf.writeln('    } on TypeError {');
      buf.writeln('      // Try next variant');
      buf.writeln('    }');
    }

    final typeList = triedTypes.join(', ');
    buf.writeln(
      "    throw FormatException("
      "'No variant of $baseName matched. Tried: $typeList');",
    );
  }

  void _writeVariantClass(
    StringBuffer buf,
    String baseName,
    ApiSchema variant,
  ) {
    final variantClassName = _variantClassName(baseName, variant);
    final variantType = _variantDartType(variant);

    buf.writeln('class $variantClassName extends $baseName {');

    // Constructor
    buf.writeln('  $variantClassName(this.value);');
    buf.writeln();

    // Value field
    buf.writeln('  final $variantType value;');
    buf.writeln();

    // toJson
    buf.writeln('  @override');
    buf.writeln('  Map<String, dynamic> toJson() => value.toJson();');
    buf.writeln();

    // == operator
    buf.writeln('  @override');
    buf.writeln('  bool operator ==(Object other) =>');
    buf.writeln('      identical(this, other) ||');
    buf.writeln('      other is $variantClassName && value == other.value;');
    buf.writeln();

    // hashCode
    buf.writeln('  @override');
    buf.writeln('  int get hashCode => value.hashCode;');
    buf.writeln();

    // toString
    buf.writeln('  @override');
    buf.writeln("  String toString() => '$variantClassName(\$value)';");

    buf.writeln('}');
  }

  /// Derive variant class name: BaseName + VariantSchemaName.
  String _variantClassName(String baseName, ApiSchema variant) {
    if (variant.name != null) {
      final variantName = nameResolver.resolveClassName(variant.name!);
      return '$baseName$variantName';
    }
    // Unnamed primitive variant — use type name
    return '$baseName${_primitiveTypeName(variant)}';
  }

  /// Get the Dart type string for a variant schema.
  String _variantDartType(ApiSchema variant) {
    if (variant.name != null) {
      return nameResolver.resolveClassName(variant.name!);
    }
    diagnostics.add(Diagnostic(
      message: 'Union variant without name — using dynamic',
      schemaPath: variant.schemaPath,
      severity: DiagnosticSeverity.warning,
    ));
    return 'dynamic';
  }

  /// Human-readable name for a primitive type (used in variant class names).
  String _primitiveTypeName(ApiSchema schema) {
    return switch (schema.type) {
      SchemaType.string => 'String',
      SchemaType.integer => 'Int',
      SchemaType.number => 'Double',
      SchemaType.boolean => 'Bool',
      SchemaType.array => 'List',
      SchemaType.object => 'Object',
      _ => 'Unknown',
    };
  }
}
