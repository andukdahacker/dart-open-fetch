import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';
import 'package:dart_open_fetch_core/src/parser/schema_parser.dart';
import 'package:test/test.dart';

void main() {
  late SchemaParser parser;

  setUp(() {
    parser = SchemaParser();
  });

  group('SchemaParser', () {
    test('parses primitive string type', () {
      final schema = parser.parseSchema({'type': 'string'});
      expect(schema.type, SchemaType.string);
      expect(schema.nullable, false);
    });

    test('parses integer type', () {
      final schema = parser.parseSchema({'type': 'integer', 'format': 'int64'});
      expect(schema.type, SchemaType.integer);
      expect(schema.format, 'int64');
    });

    test('parses boolean type', () {
      final schema = parser.parseSchema({'type': 'boolean'});
      expect(schema.type, SchemaType.boolean);
    });

    test('parses nullable string (3.0 style)', () {
      final schema = parser.parseSchema({'type': 'string', 'nullable': true});
      expect(schema.type, SchemaType.string);
      expect(schema.nullable, true);
    });

    test('parses enum values', () {
      final schema = parser.parseSchema({
        'type': 'string',
        'enum': ['active', 'inactive', 'pending'],
      });
      expect(schema.isEnum, true);
      expect(schema.enumValues, ['active', 'inactive', 'pending']);
    });

    test('parses array with items', () {
      final schema = parser.parseSchema({
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(schema.isArray, true);
      expect(schema.items, isNotNull);
      expect(schema.items!.type, SchemaType.string);
    });

    test('parses object with properties', () {
      final schema = parser.parseSchema({
        'type': 'object',
        'required': ['id', 'name'],
        'properties': {
          'id': {'type': 'integer'},
          'name': {'type': 'string'},
          'email': {'type': 'string', 'format': 'email'},
        },
      });
      expect(schema.isObject, true);
      expect(schema.properties, hasLength(3));
      expect(schema.requiredProperties, {'id', 'name'});
      expect(schema.properties[0].name, 'id');
      expect(schema.properties[0].schema.type, SchemaType.integer);
    });

    test('parses additionalProperties with schema', () {
      final schema = parser.parseSchema({
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      });
      expect(schema.hasAdditionalProperties, true);
      expect(schema.additionalProperties, isNotNull);
      expect(schema.additionalProperties!.type, SchemaType.string);
    });

    test('parses additionalProperties true → free-form map', () {
      final schema = parser.parseSchema({
        'type': 'object',
        'additionalProperties': true,
      });
      expect(schema.hasAdditionalProperties, true);
      expect(schema.additionalProperties, isNull); // null = Map<String, dynamic>
    });

    test('parses free-form object', () {
      final schema = parser.parseSchema({'type': 'object'});
      expect(schema.isFreeFormObject, true);
    });

    test('parses object with both properties and additionalProperties', () {
      final schema = parser.parseSchema({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'additionalProperties': {'type': 'integer'},
      });
      expect(schema.hasNamedAndAdditionalProperties, true);
      expect(schema.properties, hasLength(1));
      expect(schema.additionalProperties!.type, SchemaType.integer);
    });

    test('parses allOf and flattens properties', () {
      final schema = parser.parseSchema({
        'allOf': [
          {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
            },
            'required': ['id'],
          },
          {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
            'required': ['name'],
          },
        ],
      });
      expect(schema.properties, hasLength(2));
      expect(schema.requiredProperties, {'id', 'name'});
    });

    test('allOf with type conflict uses dynamic and logs warning', () {
      final schema = parser.parseSchema({
        'allOf': [
          {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
            },
          },
        ],
      });
      expect(schema.properties, hasLength(1));
      expect(schema.properties.first.schema.type, SchemaType.dynamic_);
      expect(parser.diagnostics, hasLength(1));
      expect(
        parser.diagnostics.first.message,
        contains('allOf type conflict'),
      );
    });

    test('allOf deduplicates same-name-same-type', () {
      final schema = parser.parseSchema({
        'allOf': [
          {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
        ],
      });
      expect(schema.properties, hasLength(1));
      expect(parser.diagnostics, isEmpty);
    });

    test('parses oneOf with discriminator', () {
      final schema = parser.parseSchema({
        'oneOf': [
          {
            'type': 'object',
            'properties': {
              'type': {'type': 'string'},
            },
          },
          {
            'type': 'object',
            'properties': {
              'type': {'type': 'string'},
            },
          },
        ],
        'discriminator': {
          'propertyName': 'type',
          'mapping': {
            'cat': '#/components/schemas/Cat',
            'dog': '#/components/schemas/Dog',
          },
        },
      });
      expect(schema.isComposed, true);
      expect(schema.oneOf, hasLength(2));
      expect(schema.discriminator, isNotNull);
      expect(schema.discriminator!.propertyName, 'type');
      expect(schema.discriminator!.mapping, {'cat': 'Cat', 'dog': 'Dog'});
    });

    test('parses anyOf as composed type', () {
      final schema = parser.parseSchema({
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      });
      expect(schema.isComposed, true);
      expect(schema.anyOf, hasLength(2));
    });

    test('parses deprecated schema', () {
      final schema = parser.parseSchema({
        'type': 'string',
        'deprecated': true,
      });
      expect(schema.deprecated, true);
    });

    test('parses deprecated property', () {
      final schema = parser.parseSchema({
        'type': 'object',
        'properties': {
          'oldField': {'type': 'string', 'deprecated': true},
        },
      });
      expect(schema.properties.first.deprecated, true);
    });

    test('parseComponents extracts all named schemas', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
            'Error': {
              'type': 'object',
              'properties': {
                'message': {'type': 'string'},
              },
            },
          },
        },
      });
      expect(schemas, hasLength(2));
      expect(schemas[0].name, 'Pet');
      expect(schemas[1].name, 'Error');
    });
  });

  group(r'$ref resolution', () {
    test(r'resolves $ref to component schema', () {
      parser.parseComponents({
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      });

      final schema = parser.parseSchema(
        {r'$ref': '#/components/schemas/Pet'},
        path: '#/test',
      );

      expect(schema.name, 'Pet');
      expect(schema.isObject, true);
      expect(schema.properties, hasLength(1));
      expect(schema.properties[0].name, 'name');
    });

    test(r'$ref returns same ApiSchema instance (pointer sharing)', () {
      parser.parseComponents({
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      });

      final a = parser.parseSchema({r'$ref': '#/components/schemas/Pet'});
      final b = parser.parseSchema({r'$ref': '#/components/schemas/Pet'});

      expect(identical(a, b), true);
    });

    test(r'handles circular $ref in component schemas', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Node': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
                'child': {r'$ref': '#/components/schemas/Node'},
              },
            },
          },
        },
      });

      expect(schemas, hasLength(1));
      final node = schemas[0];
      expect(node.name, 'Node');
      expect(node.properties, hasLength(2));

      final childProp = node.properties.firstWhere((p) => p.name == 'child');
      expect(childProp.schema.isCircularRef, true);
      expect(childProp.schema.refTarget, 'Node');
    });

    test(r'allOf with $ref resolves properties from target', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Animal': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
              'required': ['name'],
            },
            'Cat': {
              'allOf': [
                {r'$ref': '#/components/schemas/Animal'},
                {
                  'type': 'object',
                  'properties': {
                    'color': {'type': 'string'},
                  },
                },
              ],
            },
          },
        },
      });

      final cat = schemas.firstWhere((s) => s.name == 'Cat');
      expect(cat.properties, hasLength(2));
      expect(cat.properties.map((p) => p.name).toSet(), {'name', 'color'});
      expect(cat.requiredProperties, contains('name'));
    });

    test(r'resolves $ref-to-$ref chain', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
            'PetAlias': {r'$ref': '#/components/schemas/Pet'},
          },
        },
      });

      final pet = schemas.firstWhere((s) => s.name == 'Pet');
      final alias = parser.parseSchema(
        {r'$ref': '#/components/schemas/PetAlias'},
      );

      // PetAlias resolves through to Pet — same shared instance
      expect(identical(alias, pet), true);
      expect(alias.isObject, true);
      expect(alias.properties, hasLength(1));
    });

    test(r'emits diagnostic for $ref before parseComponents', () {
      // Calling parseSchema with $ref before parseComponents should
      // emit a diagnostic and return dynamic fallback — not crash.
      final schema = parser.parseSchema(
        {r'$ref': '#/components/schemas/Foo'},
        path: '#/test',
      );

      expect(schema.type, SchemaType.dynamic_);
      expect(
        parser.diagnostics.any((d) => d.message.contains('Foo')),
        true,
      );
    });

    test(r'circular $ref stubs share same instance', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Tree': {
              'type': 'object',
              'properties': {
                'left': {r'$ref': '#/components/schemas/Tree'},
                'right': {r'$ref': '#/components/schemas/Tree'},
              },
            },
          },
        },
      });

      final tree = schemas[0];
      final leftStub = tree.properties.firstWhere((p) => p.name == 'left').schema;
      final rightStub = tree.properties.firstWhere((p) => p.name == 'right').schema;

      expect(leftStub.isCircularRef, true);
      expect(rightStub.isCircularRef, true);
      // Both circular stubs should be the same shared instance
      expect(identical(leftStub, rightStub), true);
    });

    test('parseComponents is idempotent', () {
      parser.parseComponents({
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      });

      // Call again with different schemas — should replace, not append
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'User': {
              'type': 'object',
              'properties': {
                'email': {'type': 'string'},
              },
            },
          },
        },
      });

      expect(schemas, hasLength(1));
      expect(schemas[0].name, 'User');

      // Old schema should no longer be resolvable
      final old = parser.parseSchema(
        {r'$ref': '#/components/schemas/Pet'},
        path: '#/test',
      );
      expect(old.type, SchemaType.dynamic_);
    });

    test(r'circular stub is not equal to full schema', () {
      final schemas = parser.parseComponents({
        'components': {
          'schemas': {
            'Node': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
                'child': {r'$ref': '#/components/schemas/Node'},
              },
            },
          },
        },
      });

      final fullNode = schemas[0];
      final circularStub =
          fullNode.properties.firstWhere((p) => p.name == 'child').schema;

      // Full schema and circular stub have the same name but must not be equal
      expect(fullNode.name, circularStub.name);
      expect(fullNode == circularStub, false);
    });

    test(r'emits diagnostic for missing schema ref', () {
      parser.parseComponents({
        'components': {
          'schemas': <String, dynamic>{},
        },
      });

      final schema = parser.parseSchema(
        {r'$ref': '#/components/schemas/DoesNotExist'},
        path: '#/test',
      );

      expect(schema.type, SchemaType.dynamic_);
      expect(
        parser.diagnostics.any((d) => d.message.contains('DoesNotExist')),
        true,
      );
    });
  });
}
