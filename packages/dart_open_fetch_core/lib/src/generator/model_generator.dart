import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

import '../diagnostic.dart';
import '../ir/api_schema.dart';
import 'name_resolver.dart';

/// Generates Dart model classes from ApiSchema IR nodes.
class ModelGenerator {
  ModelGenerator({required this.nameResolver});

  final NameResolver nameResolver;
  final List<Diagnostic> diagnostics = [];

  /// Generate a Dart source string for a single object schema.
  String generateModel(ApiSchema schema) {
    final className = nameResolver.resolveClassName(schema.name!);
    final library = Library((b) {
      b.body.add(_buildClass(schema, className));
    });
    return _emit(library);
  }

  /// Generate a Dart source string for a single enum schema.
  String generateEnum(ApiSchema schema) {
    final enumName = nameResolver.resolveClassName(schema.name!);
    final library = Library((b) {
      b.body.add(_buildEnum(schema, enumName));
    });
    return _emit(library);
  }

  Class _buildClass(ApiSchema schema, String className) {
    final properties = _resolveProperties(schema);
    final hasAdditionalProps = schema.hasNamedAndAdditionalProperties;
    final additionalPropsSchema = schema.additionalProperties;

    return Class((b) {
      b.name = className;

      if (schema.deprecated) {
        b.annotations.add(
          refer("Deprecated").call([literalString('Deprecated in API spec')]),
        );
      }

      // Constructor
      b.constructors.add(_buildConstructor(
        properties,
        hasAdditionalProps: hasAdditionalProps,
        additionalPropsSchema: additionalPropsSchema,
      ));

      // Fields
      for (final prop in properties) {
        b.fields.add(_buildField(prop, schema.requiredProperties));
      }
      if (hasAdditionalProps) {
        b.fields.add(_buildAdditionalPropertiesField(additionalPropsSchema));
      }

      // fromJson factory
      b.constructors.add(_buildFromJson(
        className,
        properties,
        schema.requiredProperties,
        hasAdditionalProps: hasAdditionalProps,
        additionalPropsSchema: additionalPropsSchema,
      ));

      // toJson method
      b.methods.add(_buildToJson(
        properties,
        schema.requiredProperties,
        hasAdditionalProps: hasAdditionalProps,
      ));

      // copyWith method
      b.methods.add(_buildCopyWith(
        className,
        properties,
        schema.requiredProperties,
        hasAdditionalProps: hasAdditionalProps,
        additionalPropsSchema: additionalPropsSchema,
      ));

      // == operator
      b.methods.add(_buildEquals(
        className,
        properties,
        hasAdditionalProps: hasAdditionalProps,
      ));

      // hashCode
      b.methods.add(_buildHashCode(
        properties,
        hasAdditionalProps: hasAdditionalProps,
      ));

      // toString
      b.methods.add(_buildToString(className, properties));
    });
  }

  Constructor _buildConstructor(
    List<ApiProperty> properties, {
    required bool hasAdditionalProps,
    ApiSchema? additionalPropsSchema,
  }) {
    return Constructor((b) {
      b.constant = false;
      for (final prop in properties) {
        b.optionalParameters.add(Parameter((p) {
          p.name = NameResolver.resolveFieldName(prop.name);
          p.named = true;
          p.required =
              prop.schema.nullable == false && prop.schema.defaultValue == null;
          p.toThis = true;
        }));
      }
      if (hasAdditionalProps) {
        b.optionalParameters.add(Parameter((p) {
          p.name = 'additionalProperties';
          p.named = true;
          p.toThis = true;
          p.defaultTo = const Code('const {}');
        }));
      }
    });
  }

  Field _buildField(ApiProperty prop, Set<String> required) {
    final fieldName = NameResolver.resolveFieldName(prop.name);
    final isRequired = required.contains(prop.name);
    final dartType = _dartType(prop.schema, isRequired: isRequired);

    return Field((b) {
      b.name = fieldName;
      b.modifier = FieldModifier.final$;
      b.type = refer(dartType);
      if (prop.deprecated) {
        b.annotations.add(
          refer("Deprecated").call([literalString('Deprecated in API spec')]),
        );
      }
      if (!isRequired &&
          !prop.schema.nullable &&
          prop.schema.defaultValue != null) {
        // Non-required with default — no annotation needed
      }
    });
  }

  Field _buildAdditionalPropertiesField(ApiSchema? schema) {
    final valueType = schema != null ? _dartType(schema) : 'dynamic';
    return Field((b) {
      b.name = 'additionalProperties';
      b.modifier = FieldModifier.final$;
      b.type = refer('Map<String, $valueType>');
    });
  }

  Constructor _buildFromJson(
    String className,
    List<ApiProperty> properties,
    Set<String> required, {
    required bool hasAdditionalProps,
    ApiSchema? additionalPropsSchema,
  }) {
    final body = StringBuffer();
    body.writeln('return $className(');
    for (final prop in properties) {
      final fieldName = NameResolver.resolveFieldName(prop.name);
      final jsonKey = prop.name;
      final isRequired = required.contains(prop.name);
      final expr = _fromJsonExpression("json['$jsonKey']", prop.schema,
          isRequired: isRequired);
      body.writeln('  $fieldName: $expr,');
    }
    if (hasAdditionalProps) {
      final knownKeys = properties.map((p) => "'${p.name}'").join(', ');
      final valueType = additionalPropsSchema != null
          ? _dartType(additionalPropsSchema)
          : 'dynamic';
      body.writeln(
          '  additionalProperties: Map<String, $valueType>.fromEntries(');
      body.writeln('    json.entries');
      body.writeln('      .where((e) => !const {$knownKeys}.contains(e.key))');
      if (valueType == 'dynamic') {
        body.writeln('      .map((e) => MapEntry(e.key, e.value)),');
      } else {
        body.writeln(
            '      .map((e) => MapEntry(e.key, e.value as $valueType)),');
      }
      body.writeln('  ),');
    }
    body.writeln(');');

    return Constructor((b) {
      b.factory = true;
      b.name = 'fromJson';
      b.requiredParameters.add(Parameter((p) {
        p.name = 'json';
        p.type = refer('Map<String, dynamic>');
      }));
      b.body = Code(body.toString());
      b.lambda = false;
    });
  }

  Method _buildToJson(
    List<ApiProperty> properties,
    Set<String> required, {
    required bool hasAdditionalProps,
  }) {
    final lines = StringBuffer();
    if (hasAdditionalProps) {
      lines.writeln('final map = <String, dynamic>{');
    } else {
      lines.writeln('return <String, dynamic>{');
    }
    for (final prop in properties) {
      final fieldName = NameResolver.resolveFieldName(prop.name);
      final jsonKey = prop.name;
      final isRequired = required.contains(prop.name);
      final expr =
          _toJsonExpression(fieldName, prop.schema, isRequired: isRequired);
      lines.writeln("  '$jsonKey': $expr,");
    }
    lines.writeln('};');
    if (hasAdditionalProps) {
      lines.writeln('map.addAll(additionalProperties.map(');
      lines.writeln('  (k, v) => MapEntry(k, v),');
      lines.writeln('));');
      lines.writeln('return map;');
    }

    return Method((b) {
      b.name = 'toJson';
      b.returns = refer('Map<String, dynamic>');
      b.body = Code(lines.toString());
    });
  }

  Method _buildCopyWith(
    String className,
    List<ApiProperty> properties,
    Set<String> required, {
    required bool hasAdditionalProps,
    ApiSchema? additionalPropsSchema,
  }) {
    return Method((b) {
      b.name = 'copyWith';
      b.returns = refer(className);
      for (final prop in properties) {
        final fieldName = NameResolver.resolveFieldName(prop.name);
        final isRequired = required.contains(prop.name);
        final isNullable = !isRequired || prop.schema.nullable;
        final dartType = _dartType(prop.schema, isRequired: isRequired);

        if (isNullable) {
          // Nullable fields use callback pattern to distinguish
          // "not provided" from "set to null"
          b.optionalParameters.add(Parameter((p) {
            p.name = fieldName;
            p.named = true;
            p.type = refer('$dartType Function()?');
          }));
        } else {
          b.optionalParameters.add(Parameter((p) {
            p.name = fieldName;
            p.named = true;
            p.type = refer('$dartType?');
          }));
        }
      }
      if (hasAdditionalProps) {
        final valueType = additionalPropsSchema != null
            ? _dartType(additionalPropsSchema)
            : 'dynamic';
        b.optionalParameters.add(Parameter((p) {
          p.name = 'additionalProperties';
          p.named = true;
          p.type = refer('Map<String, $valueType>?');
        }));
      }

      final args = StringBuffer();
      args.writeln('return $className(');
      for (final prop in properties) {
        final fieldName = NameResolver.resolveFieldName(prop.name);
        final isRequired = required.contains(prop.name);
        final isNullable = !isRequired || prop.schema.nullable;
        if (isNullable) {
          args.writeln(
              '  $fieldName: $fieldName != null ? $fieldName() : this.$fieldName,');
        } else {
          args.writeln('  $fieldName: $fieldName ?? this.$fieldName,');
        }
      }
      if (hasAdditionalProps) {
        args.writeln(
            '  additionalProperties: additionalProperties ?? this.additionalProperties,');
      }
      args.writeln(');');

      b.body = Code(args.toString());
    });
  }

  Method _buildEquals(
    String className,
    List<ApiProperty> properties, {
    required bool hasAdditionalProps,
  }) {
    final conditions = StringBuffer();
    conditions.write('identical(this, other) || other is $className');
    for (final prop in properties) {
      final fieldName = NameResolver.resolveFieldName(prop.name);
      if (_isCollectionType(prop.schema)) {
        conditions.write(' && _deepEquals($fieldName, other.$fieldName)');
      } else {
        conditions.write(' && $fieldName == other.$fieldName');
      }
    }
    if (hasAdditionalProps) {
      conditions.write(
        ' && _deepEquals(additionalProperties, other.additionalProperties)',
      );
    }

    return Method((b) {
      b.name = 'operator ==';
      b.returns = refer('bool');
      b.annotations.add(refer('override'));
      b.requiredParameters.add(Parameter((p) {
        p.name = 'other';
        p.type = refer('Object');
      }));
      b.lambda = true;
      b.body = Code(conditions.toString());
    });
  }

  Method _buildHashCode(
    List<ApiProperty> properties, {
    required bool hasAdditionalProps,
  }) {
    final hashArgs = <String>[];
    for (final prop in properties) {
      final fieldName = NameResolver.resolveFieldName(prop.name);
      if (_isCollectionType(prop.schema)) {
        hashArgs.add('_deepHash($fieldName)');
      } else {
        hashArgs.add(fieldName);
      }
    }
    if (hasAdditionalProps) {
      hashArgs.add('_deepHash(additionalProperties)');
    }

    final hashExpr = hashArgs.length <= 20
        ? 'Object.hash(${hashArgs.join(', ')})'
        : 'Object.hashAll([${hashArgs.join(', ')}])';

    return Method((b) {
      b.name = 'hashCode';
      b.type = MethodType.getter;
      b.returns = refer('int');
      b.annotations.add(refer('override'));
      b.lambda = true;
      b.body = Code(hashExpr);
    });
  }

  bool _isCollectionType(ApiSchema schema) {
    return schema.isArray ||
        schema.isFreeFormObject ||
        (schema.type == SchemaType.object && schema.name == null);
  }

  Method _buildToString(String className, List<ApiProperty> properties) {
    final fields = properties.map((p) {
      final fieldName = NameResolver.resolveFieldName(p.name);
      return '$fieldName: \$$fieldName';
    }).join(', ');

    return Method((b) {
      b.name = 'toString';
      b.returns = refer('String');
      b.annotations.add(refer('override'));
      b.lambda = true;
      b.body = Code("'$className($fields)'");
    });
  }

  Enum _buildEnum(ApiSchema schema, String enumName) {
    final values = schema.enumValues!;
    return Enum((b) {
      b.name = enumName;

      if (schema.deprecated) {
        b.annotations.add(
          refer("Deprecated").call([literalString('Deprecated in API spec')]),
        );
      }

      // Enum values
      for (final value in values) {
        final memberName = NameResolver.resolveEnumValue(value);
        b.values.add(EnumValue((v) {
          v.name = memberName;
          v.arguments.add(literalString(value));
        }));
      }

      // Constructor
      b.constructors.add(Constructor((c) {
        c.constant = true;
        c.requiredParameters.add(Parameter((p) {
          p.name = 'value';
          p.toThis = true;
        }));
      }));

      // Value field
      b.fields.add(Field((f) {
        f.name = 'value';
        f.type = refer('String');
        f.modifier = FieldModifier.final$;
      }));

      // fromJson static method
      b.methods.add(Method((m) {
        m.name = 'fromJson';
        m.static = true;
        m.returns = refer(enumName);
        m.requiredParameters.add(Parameter((p) {
          p.name = 'json';
          p.type = refer('String');
        }));
        final cases = values.map((v) {
          final memberName = NameResolver.resolveEnumValue(v);
          return "      '$v' => $enumName.$memberName,";
        }).join('\n');
        m.body = Code('''
return switch (json) {
$cases
      _ => throw FormatException('Unknown $enumName value: \$json'),
    };
''');
      }));

      // toJson method
      b.methods.add(Method((m) {
        m.name = 'toJson';
        m.returns = refer('String');
        m.lambda = true;
        m.body = const Code('value');
      }));
    });
  }

  // --- Type mapping helpers ---

  /// Map an ApiSchema to a Dart type string.
  String _dartType(ApiSchema schema, {bool isRequired = true}) {
    final nullSuffix = (!isRequired || schema.nullable) ? '?' : '';

    if (schema.isCircularRef && schema.refTarget != null) {
      final resolved = nameResolver.resolveClassName(schema.refTarget!);
      return '$resolved$nullSuffix';
    }

    // Named schemas always use their class name, even if they look free-form
    // (the schema might just be a reference with no inline properties)
    if (schema.name != null && !schema.isPrimitive && !schema.isArray) {
      return '${nameResolver.resolveClassName(schema.name!)}$nullSuffix';
    }

    if (schema.isFreeFormObject) {
      return 'Map<String, dynamic>$nullSuffix';
    }

    if (schema.isEnum && schema.name != null) {
      return '${nameResolver.resolveClassName(schema.name!)}$nullSuffix';
    }

    if (schema.isComposed && schema.name != null) {
      return '${nameResolver.resolveClassName(schema.name!)}$nullSuffix';
    }

    switch (schema.type) {
      case SchemaType.string:
        return 'String$nullSuffix';
      case SchemaType.integer:
        return 'int$nullSuffix';
      case SchemaType.number:
        if (schema.format == 'float' || schema.format == 'double') {
          return 'double$nullSuffix';
        }
        return 'double$nullSuffix';
      case SchemaType.boolean:
        return 'bool$nullSuffix';
      case SchemaType.array:
        if (schema.items != null) {
          final itemType = _dartType(schema.items!);
          return 'List<$itemType>$nullSuffix';
        }
        return 'List<dynamic>$nullSuffix';
      case SchemaType.object:
        if (schema.name != null) {
          return '${nameResolver.resolveClassName(schema.name!)}$nullSuffix';
        }
        if (schema.hasAdditionalProperties &&
            schema.additionalProperties != null) {
          final valueType = _dartType(schema.additionalProperties!);
          return 'Map<String, $valueType>$nullSuffix';
        }
        return 'Map<String, dynamic>$nullSuffix';
      case SchemaType.composed:
        if (schema.name != null) {
          return '${nameResolver.resolveClassName(schema.name!)}$nullSuffix';
        }
        return 'dynamic';
      case SchemaType.dynamic_:
        return 'dynamic';
    }
  }

  /// Generate a fromJson expression for a given schema.
  String _fromJsonExpression(String accessor, ApiSchema schema,
      {bool isRequired = true}) {
    final isNullable = !isRequired || schema.nullable;

    if (schema.isFreeFormObject) {
      if (isNullable) {
        return '$accessor != null ? Map<String, dynamic>.from($accessor as Map) : null';
      }
      return 'Map<String, dynamic>.from($accessor as Map)';
    }

    if (schema.isCircularRef && schema.refTarget != null) {
      final className = nameResolver.resolveClassName(schema.refTarget!);
      if (isNullable) {
        return '$accessor != null ? $className.fromJson($accessor as Map<String, dynamic>) : null';
      }
      return '$className.fromJson($accessor as Map<String, dynamic>)';
    }

    if (schema.isEnum && schema.name != null) {
      final enumName = nameResolver.resolveClassName(schema.name!);
      if (isNullable) {
        return '$accessor != null ? $enumName.fromJson($accessor as String) : null';
      }
      return '$enumName.fromJson($accessor as String)';
    }

    if (schema.isComposed && schema.name != null) {
      final className = nameResolver.resolveClassName(schema.name!);
      if (isNullable) {
        return '$accessor != null ? $className.fromJson($accessor as Map<String, dynamic>) : null';
      }
      return '$className.fromJson($accessor as Map<String, dynamic>)';
    }

    switch (schema.type) {
      case SchemaType.string:
        if (isNullable) return '$accessor as String?';
        return '$accessor as String';
      case SchemaType.integer:
        if (isNullable) {
          return '$accessor != null ? ($accessor as num).toInt() : null';
        }
        return '($accessor as num).toInt()';
      case SchemaType.number:
        if (isNullable) {
          return '$accessor != null ? ($accessor as num).toDouble() : null';
        }
        return '($accessor as num).toDouble()';
      case SchemaType.boolean:
        if (isNullable) return '$accessor as bool?';
        return '$accessor as bool';
      case SchemaType.array:
        final itemExpr =
            schema.items != null ? _fromJsonListItem('e', schema.items!) : 'e';
        if (isNullable) {
          return '$accessor != null ? ($accessor as List<dynamic>).map((e) => $itemExpr).toList() : null';
        }
        return '($accessor as List<dynamic>).map((e) => $itemExpr).toList()';
      case SchemaType.object:
        if (schema.name != null) {
          final className = nameResolver.resolveClassName(schema.name!);
          if (isNullable) {
            return '$accessor != null ? $className.fromJson($accessor as Map<String, dynamic>) : null';
          }
          return '$className.fromJson($accessor as Map<String, dynamic>)';
        }
        if (schema.hasAdditionalProperties &&
            schema.additionalProperties != null) {
          final valueType = _dartType(schema.additionalProperties!);
          if (isNullable) {
            return '$accessor != null ? ($accessor as Map<String, dynamic>).map((k, v) => MapEntry(k, v as $valueType)) : null';
          }
          return '($accessor as Map<String, dynamic>).map((k, v) => MapEntry(k, v as $valueType))';
        }
        if (isNullable) {
          return '$accessor != null ? Map<String, dynamic>.from($accessor as Map) : null';
        }
        return 'Map<String, dynamic>.from($accessor as Map)';
      case SchemaType.composed:
        if (schema.name != null) {
          final className = nameResolver.resolveClassName(schema.name!);
          if (isNullable) {
            return '$accessor != null ? $className.fromJson($accessor as Map<String, dynamic>) : null';
          }
          return '$className.fromJson($accessor as Map<String, dynamic>)';
        }
        return accessor;
      case SchemaType.dynamic_:
        return accessor;
    }
  }

  /// Expression to convert a list element from JSON.
  String _fromJsonListItem(String accessor, ApiSchema schema) {
    if (schema.isEnum && schema.name != null) {
      final enumName = nameResolver.resolveClassName(schema.name!);
      return '$enumName.fromJson($accessor as String)';
    }
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      final className = nameResolver.resolveClassName(schema.name!);
      return '$className.fromJson($accessor as Map<String, dynamic>)';
    }
    switch (schema.type) {
      case SchemaType.string:
        return '$accessor as String';
      case SchemaType.integer:
        return '($accessor as num).toInt()';
      case SchemaType.number:
        return '($accessor as num).toDouble()';
      case SchemaType.boolean:
        return '$accessor as bool';
      case SchemaType.array:
        if (schema.items != null) {
          final inner = _fromJsonListItem('i', schema.items!);
          return '($accessor as List<dynamic>).map((i) => $inner).toList()';
        }
        return '$accessor as List<dynamic>';
      case SchemaType.object:
        return 'Map<String, dynamic>.from($accessor as Map)';
      default:
        return accessor;
    }
  }

  /// Generate a toJson expression for a field.
  String _toJsonExpression(String fieldName, ApiSchema schema,
      {bool isRequired = true}) {
    final isNullable = !isRequired || schema.nullable;

    if (schema.isFreeFormObject) {
      return fieldName;
    }

    if (schema.isCircularRef && schema.refTarget != null) {
      if (isNullable) return '$fieldName?.toJson()';
      return '$fieldName.toJson()';
    }

    if (schema.isEnum && schema.name != null) {
      if (isNullable) return '$fieldName?.toJson()';
      return '$fieldName.toJson()';
    }

    if (schema.isComposed && schema.name != null) {
      if (isNullable) return '$fieldName?.toJson()';
      return '$fieldName.toJson()';
    }

    switch (schema.type) {
      case SchemaType.string:
      case SchemaType.integer:
      case SchemaType.number:
      case SchemaType.boolean:
      case SchemaType.dynamic_:
        return fieldName;
      case SchemaType.array:
        if (schema.items != null && _needsToJson(schema.items!)) {
          final itemExpr = _toJsonListItem('e', schema.items!);
          if (isNullable) {
            return '$fieldName?.map((e) => $itemExpr).toList()';
          }
          return '$fieldName.map((e) => $itemExpr).toList()';
        }
        return fieldName;
      case SchemaType.object:
        if (schema.name != null) {
          if (isNullable) return '$fieldName?.toJson()';
          return '$fieldName.toJson()';
        }
        return fieldName;
      case SchemaType.composed:
        if (schema.name != null) {
          if (isNullable) return '$fieldName?.toJson()';
          return '$fieldName.toJson()';
        }
        return fieldName;
    }
  }

  String _toJsonListItem(String accessor, ApiSchema schema) {
    if (schema.isEnum && schema.name != null) {
      return '$accessor.toJson()';
    }
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      return '$accessor.toJson()';
    }
    if (schema.isArray && schema.items != null && _needsToJson(schema.items!)) {
      final inner = _toJsonListItem('i', schema.items!);
      return '$accessor.map((i) => $inner).toList()';
    }
    return accessor;
  }

  bool _needsToJson(ApiSchema schema) {
    if (schema.isEnum && schema.name != null) return true;
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      return true;
    }
    if (schema.isArray && schema.items != null) {
      return _needsToJson(schema.items!);
    }
    return false;
  }

  List<ApiProperty> _resolveProperties(ApiSchema schema) {
    // For allOf schemas, properties should already be flattened by the parser.
    return schema.properties;
  }

  String _emit(Library library) {
    final emitter = DartEmitter.scoped(useNullSafetySyntax: true);
    final source = library.accept(emitter).toString();
    try {
      return DartFormatter(languageVersion: Version(3, 5, 0)).format(source);
    } catch (_) {
      // If formatting fails, return unformatted (will be caught by compile test)
      return source;
    }
  }
}
