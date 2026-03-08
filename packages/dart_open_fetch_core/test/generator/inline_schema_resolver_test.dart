import 'package:dart_open_fetch_core/src/generator/inline_schema_resolver.dart';
import 'package:dart_open_fetch_core/src/ir/api_schema.dart';
import 'package:test/test.dart';

void main() {
  late InlineSchemaResolver resolver;

  setUp(() {
    resolver = InlineSchemaResolver();
  });

  group('InlineSchemaResolver', () {
    test('assigns name to unnamed inline object property', () {
      final schemas = [
        ApiSchema(
          name: 'Order',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'shipping_address',
              schema: ApiSchema(
                type: SchemaType.object,
                properties: [
                  ApiProperty(
                    name: 'street',
                    schema: ApiSchema(type: SchemaType.string),
                  ),
                  ApiProperty(
                    name: 'city',
                    schema: ApiSchema(type: SchemaType.string),
                  ),
                ],
                requiredProperties: {'street', 'city'},
              ),
            ),
          ],
          requiredProperties: {'shipping_address'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      final order = resolved.first;
      final addrSchema = order.properties.first.schema;

      expect(addrSchema.name, isNotNull);
      expect(addrSchema.name, contains('Order'));
      expect(addrSchema.name, contains('Shipping'));
      expect(resolver.generatedSchemas, hasLength(1));
      expect(resolver.generatedSchemas.first.name, addrSchema.name);
      expect(resolver.generatedSchemas.first.properties, hasLength(2));
    });

    test('assigns name to unnamed inline enum property', () {
      final schemas = [
        ApiSchema(
          name: 'Pet',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'status',
              schema: ApiSchema(
                type: SchemaType.string,
                enumValues: ['available', 'pending', 'sold'],
              ),
            ),
          ],
          requiredProperties: {'status'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      final pet = resolved.first;
      final statusSchema = pet.properties.first.schema;

      expect(statusSchema.name, isNotNull);
      expect(statusSchema.name, contains('Pet'));
      expect(statusSchema.name, contains('Status'));
      expect(statusSchema.isEnum, isTrue);
      expect(resolver.generatedSchemas, hasLength(1));
    });

    test('assigns name to unnamed inline object in array items', () {
      final schemas = [
        ApiSchema(
          name: 'Response',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'items',
              schema: ApiSchema(
                type: SchemaType.array,
                items: ApiSchema(
                  type: SchemaType.object,
                  properties: [
                    ApiProperty(
                      name: 'id',
                      schema: ApiSchema(type: SchemaType.integer),
                    ),
                  ],
                  requiredProperties: {'id'},
                ),
              ),
            ),
          ],
          requiredProperties: {'items'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      final response = resolved.first;
      final itemsSchema = response.properties.first.schema;

      expect(itemsSchema.items, isNotNull);
      expect(itemsSchema.items!.name, isNotNull);
      expect(resolver.generatedSchemas, hasLength(1));
    });

    test('handles deeply nested inline objects', () {
      final schemas = [
        ApiSchema(
          name: 'Root',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'level1',
              schema: ApiSchema(
                type: SchemaType.object,
                properties: [
                  ApiProperty(
                    name: 'level2',
                    schema: ApiSchema(
                      type: SchemaType.object,
                      properties: [
                        ApiProperty(
                          name: 'value',
                          schema: ApiSchema(type: SchemaType.string),
                        ),
                      ],
                      requiredProperties: {'value'},
                    ),
                  ),
                ],
                requiredProperties: {'level2'},
              ),
            ),
          ],
          requiredProperties: {'level1'},
        ),
      ];

      resolver.resolve(schemas);
      // Should have generated schemas for both level1 and level2
      expect(resolver.generatedSchemas.length, greaterThanOrEqualTo(2));

      // All generated schemas should have names
      for (final schema in resolver.generatedSchemas) {
        expect(schema.name, isNotNull);
      }
    });

    test('skips already-named schemas', () {
      final schemas = [
        ApiSchema(
          name: 'Order',
          type: SchemaType.object,
          properties: [
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
          requiredProperties: {'pet'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      expect(resolver.generatedSchemas, isEmpty);
      expect(resolved.first.properties.first.schema.name, 'Pet');
    });

    test('avoids name collisions with existing schemas', () {
      final schemas = [
        ApiSchema(
          name: 'OrderShippingAddress',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'zip',
              schema: ApiSchema(type: SchemaType.string),
            ),
          ],
          requiredProperties: {'zip'},
        ),
        ApiSchema(
          name: 'Order',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'shipping_address',
              schema: ApiSchema(
                type: SchemaType.object,
                properties: [
                  ApiProperty(
                    name: 'street',
                    schema: ApiSchema(type: SchemaType.string),
                  ),
                ],
                requiredProperties: {'street'},
              ),
            ),
          ],
          requiredProperties: {'shipping_address'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      final inlineAddr = resolved[1].properties.first.schema;

      // Should get a suffixed name since OrderShippingAddress is taken
      expect(inlineAddr.name, isNotNull);
      expect(inlineAddr.name, isNot('OrderShippingAddress'));
    });

    test('skips free-form objects (no properties)', () {
      final schemas = [
        ApiSchema(
          name: 'Container',
          type: SchemaType.object,
          properties: [
            ApiProperty(
              name: 'metadata',
              schema: ApiSchema(
                type: SchemaType.object,
                // No properties — free-form
              ),
            ),
          ],
          requiredProperties: {'metadata'},
        ),
      ];

      final resolved = resolver.resolve(schemas);
      // Free-form objects should remain as Map<String, dynamic>
      expect(resolver.generatedSchemas, isEmpty);
      expect(resolved.first.properties.first.schema.name, isNull);
    });
  });
}
