import 'package:dart_open_fetch_core/src/parser/ref_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('RefResolver', () {
    test(r'leaves component schema $ref for SchemaParser', () async {
      final schema = <String, dynamic>{
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
        'paths': {
          '/pets': {
            'get': {
              'responses': {
                '200': {
                  'content': {
                    'application/json': {
                      'schema': {r'$ref': '#/components/schemas/Pet'},
                    },
                  },
                },
              },
            },
          },
        },
      };

      final resolver = RefResolver(
        rootSchema: schema,
        basePath: '.',
        fileReader: (_) async => throw Exception('Should not be called'),
      );
      final resolved = await resolver.resolveAll();

      final responseSchema = ((resolved['paths'] as Map)['/pets'] as Map)['get']
              ['responses']['200']['content']['application/json']['schema']
          as Map<String, dynamic>;

      // $ref is preserved for SchemaParser to resolve at IR level
      expect(responseSchema[r'$ref'], '#/components/schemas/Pet');
    });

    test(r'leaves component schema definitions untouched', () async {
      final schema = <String, dynamic>{
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
      };

      final resolver = RefResolver(
        rootSchema: schema,
        basePath: '.',
        fileReader: (_) async => throw Exception('Should not be called'),
      );
      final resolved = await resolver.resolveAll();

      final nodeSchema =
          (resolved['components'] as Map)['schemas']['Node'] as Map;
      final childProp = (nodeSchema['properties'] as Map)['child'] as Map;

      // $ref is preserved — no deep copy or circular marker
      expect(childProp[r'$ref'], '#/components/schemas/Node');
    });

    test(r'logs diagnostic for remote URL $ref', () async {
      final schema = <String, dynamic>{
        'paths': {
          '/test': {
            'get': {
              'responses': {
                '200': {
                  'content': {
                    'application/json': {
                      'schema': {
                        r'$ref': 'https://example.com/schemas/Pet.yaml'
                      },
                    },
                  },
                },
              },
            },
          },
        },
      };

      final resolver = RefResolver(
        rootSchema: schema,
        basePath: '.',
        fileReader: (_) async => throw Exception('Should not be called'),
      );
      await resolver.resolveAll();

      expect(resolver.diagnostics, hasLength(1));
      expect(
        resolver.diagnostics.first.message,
        contains('Remote URL'),
      );
    });

    test(r'leaves ref-to-ref component schemas for SchemaParser', () async {
      final schema = <String, dynamic>{
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
        'paths': {
          '/pets': {
            'get': {
              'responses': {
                '200': {
                  'content': {
                    'application/json': {
                      'schema': {r'$ref': '#/components/schemas/PetAlias'},
                    },
                  },
                },
              },
            },
          },
        },
      };

      final resolver = RefResolver(
        rootSchema: schema,
        basePath: '.',
        fileReader: (_) async => throw Exception('Should not be called'),
      );
      final resolved = await resolver.resolveAll();

      // PetAlias stays as a $ref — SchemaParser will chase the chain
      final aliasSchema =
          (resolved['components'] as Map)['schemas']['PetAlias'] as Map;
      expect(aliasSchema[r'$ref'], '#/components/schemas/Pet');
    });

    test(r'resolves non-schema $ref (parameters)', () async {
      // Use explicit <String, dynamic> / <dynamic> types to match what
      // yamlToMap and json.decode produce in real usage.
      final schema = <String, dynamic>{
        'components': <String, dynamic>{
          'parameters': <String, dynamic>{
            'LimitParam': <String, dynamic>{
              'name': 'limit',
              'in': 'query',
              'schema': <String, dynamic>{'type': 'integer'},
            },
          },
        },
        'paths': <String, dynamic>{
          '/items': <String, dynamic>{
            'get': <String, dynamic>{
              'parameters': <dynamic>[
                <String, dynamic>{r'$ref': '#/components/parameters/LimitParam'},
              ],
            },
          },
        },
      };

      final resolver = RefResolver(
        rootSchema: schema,
        basePath: '.',
        fileReader: (_) async => throw Exception('Should not be called'),
      );
      final resolved = await resolver.resolveAll();

      final params = ((resolved['paths'] as Map)['/items'] as Map)['get']
          ['parameters'] as List;
      final param = params[0] as Map<String, dynamic>;

      expect(param['name'], 'limit');
      expect(param.containsKey(r'$ref'), false);
    });
  });
}
