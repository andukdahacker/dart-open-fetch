import 'package:dart_open_fetch_core/src/generator/name_resolver.dart';
import 'package:dart_open_fetch_core/src/generator/union_generator.dart';
import 'package:dart_open_fetch_core/src/ir/api_schema.dart';
import 'package:test/test.dart';

void main() {
  late NameResolver nameResolver;
  late UnionGenerator generator;

  setUp(() {
    nameResolver = NameResolver();
    generator = UnionGenerator(nameResolver: nameResolver);
  });

  group('UnionGenerator', () {
    test('generates sealed class with discriminator', () {
      final schema = ApiSchema(
        name: 'PetOrError',
        type: SchemaType.composed,
        oneOf: [
          ApiSchema(name: 'Cat', type: SchemaType.object),
          ApiSchema(name: 'Dog', type: SchemaType.object),
        ],
        discriminator: ApiDiscriminator(
          propertyName: 'petType',
          mapping: {
            'cat': '#/components/schemas/Cat',
            'dog': '#/components/schemas/Dog',
          },
        ),
      );

      final output = generator.generateUnion(schema);
      expect(output, contains('sealed class PetOrError'));
      expect(output, contains('class PetOrErrorCat extends PetOrError'));
      expect(output, contains('class PetOrErrorDog extends PetOrError'));
      expect(output, contains("json['petType']"));
      expect(output, contains("'cat'"));
      expect(output, contains("'dog'"));
      expect(output, contains('Cat.fromJson'));
      expect(output, contains('Dog.fromJson'));
      expect(output, contains('toJson()'));
    });

    test('generates sealed class without discriminator (try-parse)', () {
      final schema = ApiSchema(
        name: 'StringOrInt',
        type: SchemaType.composed,
        oneOf: [
          ApiSchema(name: 'TypeA', type: SchemaType.object),
          ApiSchema(name: 'TypeB', type: SchemaType.object),
        ],
      );

      final output = generator.generateUnion(schema);
      expect(output, contains('sealed class StringOrInt'));
      expect(output, contains('class StringOrIntTypeA extends StringOrInt'));
      expect(output, contains('class StringOrIntTypeB extends StringOrInt'));
      expect(output, contains('try {'));
      expect(output, contains('TypeA.fromJson(json)'));
      expect(output, contains('TypeB.fromJson(json)'));
      expect(output, contains('on FormatException'));
      expect(output, contains('on TypeError'));
      expect(output, contains("throw FormatException("));
    });

    test('generates anyOf as try-parse (same as oneOf without discriminator)',
        () {
      final schema = ApiSchema(
        name: 'MixedType',
        type: SchemaType.composed,
        anyOf: [
          ApiSchema(name: 'Alpha', type: SchemaType.object),
          ApiSchema(name: 'Beta', type: SchemaType.object),
        ],
      );

      final output = generator.generateUnion(schema);
      expect(output, contains('sealed class MixedType'));
      expect(output, contains('class MixedTypeAlpha extends MixedType'));
      expect(output, contains('class MixedTypeBeta extends MixedType'));
      expect(output, contains('try {'));
    });

    test('variant classes have value field and standard methods', () {
      final schema = ApiSchema(
        name: 'MyUnion',
        type: SchemaType.composed,
        oneOf: [
          ApiSchema(name: 'Variant', type: SchemaType.object),
        ],
      );

      final output = generator.generateUnion(schema);
      expect(output, contains('final Variant value;'));
      expect(output, contains('value.toJson()'));
      expect(output, contains('operator =='));
      expect(output, contains('int get hashCode'));
      expect(output, contains('toString()'));
    });

    test('generates deprecated annotation', () {
      final schema = ApiSchema(
        name: 'OldUnion',
        type: SchemaType.composed,
        deprecated: true,
        oneOf: [
          ApiSchema(name: 'TypeX', type: SchemaType.object),
        ],
      );

      final output = generator.generateUnion(schema);
      expect(output, contains("@Deprecated('Deprecated in API spec')"));
    });

    test('handles discriminator mapping with ref paths', () {
      final schema = ApiSchema(
        name: 'Animal',
        type: SchemaType.composed,
        oneOf: [
          ApiSchema(name: 'Cat', type: SchemaType.object),
          ApiSchema(name: 'Dog', type: SchemaType.object),
        ],
        discriminator: ApiDiscriminator(
          propertyName: 'type',
          mapping: {
            'feline': '#/components/schemas/Cat',
            'canine': '#/components/schemas/Dog',
          },
        ),
      );

      final output = generator.generateUnion(schema);
      expect(output, contains("'feline'"));
      expect(output, contains("'canine'"));
    });
  });
}
