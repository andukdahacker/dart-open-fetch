import 'package:dart_open_fetch_core/src/generator/model_generator.dart';
import 'package:dart_open_fetch_core/src/generator/name_resolver.dart';
import 'package:dart_open_fetch_core/src/ir/api_schema.dart';
import 'package:test/test.dart';

void main() {
  late NameResolver nameResolver;
  late ModelGenerator generator;

  setUp(() {
    nameResolver = NameResolver();
    generator = ModelGenerator(nameResolver: nameResolver);
  });

  group('ModelGenerator', () {
    test('generates simple object class', () {
      final schema = ApiSchema(
        name: 'Pet',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'id',
            schema: ApiSchema(type: SchemaType.integer),
          ),
          ApiProperty(
            name: 'name',
            schema: ApiSchema(type: SchemaType.string),
          ),
          ApiProperty(
            name: 'tag',
            schema: ApiSchema(type: SchemaType.string, nullable: true),
          ),
        ],
        requiredProperties: {'id', 'name'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains('class Pet'));
      expect(output, contains('final int id;'));
      expect(output, contains('final String name;'));
      expect(output, contains('final String? tag;'));
      expect(output, contains('factory Pet.fromJson(Map<String, dynamic> json)'));
      expect(output, contains('Map<String, dynamic> toJson()'));
      expect(output, contains('Pet copyWith('));
      expect(output, contains('operator =='));
      expect(output, contains('int get hashCode'));
      expect(output, contains('String toString()'));
    });

    test('generates class with nested object', () {
      final schema = ApiSchema(
        name: 'Order',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'id',
            schema: ApiSchema(type: SchemaType.integer),
          ),
          ApiProperty(
            name: 'pet',
            schema: ApiSchema(
              name: 'Pet',
              type: SchemaType.object,
              properties: [
                ApiProperty(
                  name: 'name',
                  schema: ApiSchema(type: SchemaType.string),
                ),
              ],
              requiredProperties: {'name'},
            ),
          ),
        ],
        requiredProperties: {'id', 'pet'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains('final Pet pet;'));
      expect(output, contains('Pet.fromJson'));
    });

    test('generates class with array property', () {
      final schema = ApiSchema(
        name: 'PetList',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'pets',
            schema: ApiSchema(
              type: SchemaType.array,
              items: ApiSchema(
                name: 'Pet',
                type: SchemaType.object,
              ),
            ),
          ),
        ],
        requiredProperties: {'pets'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains('final List<Pet> pets;'));
    });

    test('generates class with nullable fields', () {
      final schema = ApiSchema(
        name: 'User',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'email',
            schema: ApiSchema(type: SchemaType.string),
          ),
          ApiProperty(
            name: 'nickname',
            schema: ApiSchema(type: SchemaType.string),
          ),
        ],
        requiredProperties: {'email'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains('final String email;'));
      // nickname is not required, so nullable
      expect(output, contains('final String? nickname;'));
    });

    test('generates class with deprecated field', () {
      final schema = ApiSchema(
        name: 'Legacy',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'oldField',
            schema: ApiSchema(type: SchemaType.string),
            deprecated: true,
          ),
        ],
        requiredProperties: {'oldField'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains("@Deprecated('Deprecated in API spec')"));
    });

    test('generates class with additionalProperties', () {
      final schema = ApiSchema(
        name: 'Metadata',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'name',
            schema: ApiSchema(type: SchemaType.string),
          ),
        ],
        requiredProperties: {'name'},
        hasAdditionalProperties: true,
        additionalProperties: ApiSchema(type: SchemaType.string),
      );

      final output = generator.generateModel(schema);
      expect(output, contains('final String name;'));
      expect(output, contains('final Map<String, String> additionalProperties;'));
      // fromJson should filter known keys
      expect(output, contains("'name'"));
    });

    test('generates Map<String, dynamic> for free-form object', () {
      final schema = ApiSchema(
        name: 'Container',
        type: SchemaType.object,
        properties: [
          ApiProperty(
            name: 'data',
            schema: ApiSchema(
              type: SchemaType.object,
            ),
          ),
        ],
        requiredProperties: {'data'},
      );

      final output = generator.generateModel(schema);
      expect(output, contains('Map<String, dynamic>'));
    });
  });

  group('Enum generation', () {
    test('generates basic enum', () {
      final schema = ApiSchema(
        name: 'Status',
        type: SchemaType.string,
        enumValues: ['active', 'inactive', 'pending'],
      );

      final output = generator.generateEnum(schema);
      expect(output, contains('enum Status'));
      expect(output, contains('active'));
      expect(output, contains('inactive'));
      expect(output, contains('pending'));
      expect(output, contains('fromJson'));
      expect(output, contains('toJson'));
    });

    test('sanitizes enum values', () {
      final schema = ApiSchema(
        name: 'StatusCode',
        type: SchemaType.string,
        enumValues: ['in-progress', '404', 'class', ''],
      );

      final output = generator.generateEnum(schema);
      expect(output, contains('inProgress'));
      expect(output, contains('value404'));
      expect(output, contains(r'class$'));
      expect(output, contains('empty'));
    });
  });

  group('NameResolver', () {
    test('resolves duplicate class names', () {
      final resolver = NameResolver();
      expect(resolver.resolveClassName('Pet'), 'Pet');
      expect(resolver.resolveClassName('Pet'), 'Pet'); // same schema = same name
      // Simulate different schema with same name (via fresh resolver call after clearing)
    });

    test('resolves reserved word collision', () {
      final resolver = NameResolver();
      final name = resolver.resolveClassName('class');
      expect(name, r'Class$');
      expect(resolver.diagnostics, isNotEmpty);
    });

    test('resolves field names', () {
      expect(NameResolver.resolveFieldName('my_field'), 'myField');
      expect(NameResolver.resolveFieldName('class'), r'class$');
    });

    test('resolves enum values', () {
      expect(NameResolver.resolveEnumValue('in-progress'), 'inProgress');
      expect(NameResolver.resolveEnumValue('404'), 'value404');
      expect(NameResolver.resolveEnumValue('class'), r'class$');
      expect(NameResolver.resolveEnumValue(''), 'empty');
    });

    test('generates snake_case file names', () {
      final resolver = NameResolver();
      expect(resolver.resolveFileName('CreateUserRequest'),
          'create_user_request.dart');
      expect(resolver.resolveFileName('Pet'), 'pet.dart');
    });
  });
}
