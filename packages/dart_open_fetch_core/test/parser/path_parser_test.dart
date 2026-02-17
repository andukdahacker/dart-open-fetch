import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';
import 'package:dart_open_fetch_core/src/parser/path_parser.dart';
import 'package:dart_open_fetch_core/src/parser/schema_parser.dart';
import 'package:test/test.dart';

void main() {
  late PathParser pathParser;

  setUp(() {
    pathParser = PathParser(schemaParser: SchemaParser());
  });

  group('PathParser', () {
    test('parses basic GET path', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/pets': {
            'get': {
              'operationId': 'listPets',
              'summary': 'List all pets',
              'responses': {
                '200': {
                  'description': 'A list of pets',
                },
              },
            },
          },
        },
      });
      expect(paths, hasLength(1));
      expect(paths.first.path, '/pets');
      expect(paths.first.operations, hasLength(1));
      expect(paths.first.operations.first.method, 'get');
      expect(paths.first.operations.first.operationId, 'listPets');
    });

    test('generates operationId when missing', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/users/{id}': {
            'get': {
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      expect(paths.first.operations.first.operationId, 'getUsersById');
    });

    test('parses path and query parameters', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/pets/{petId}': {
            'get': {
              'operationId': 'getPet',
              'parameters': [
                {
                  'name': 'petId',
                  'in': 'path',
                  'required': true,
                  'schema': {'type': 'integer'},
                },
                {
                  'name': 'expand',
                  'in': 'query',
                  'schema': {'type': 'boolean'},
                },
              ],
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      final op = paths.first.operations.first;
      expect(op.parameters, hasLength(2));
      expect(op.parameters[0].name, 'petId');
      expect(op.parameters[0].location, ParameterLocation.path);
      expect(op.parameters[0].required_, true);
      expect(op.parameters[1].name, 'expand');
      expect(op.parameters[1].location, ParameterLocation.query);
    });

    test('parses request body', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/pets': {
            'post': {
              'operationId': 'createPet',
              'requestBody': {
                'required': true,
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'properties': {
                        'name': {'type': 'string'},
                      },
                    },
                  },
                },
              },
              'responses': {
                '201': {'description': 'Created'},
              },
            },
          },
        },
      });
      final op = paths.first.operations.first;
      expect(op.requestBody, isNotNull);
      expect(op.requestBody!.required_, true);
      expect(op.requestBody!.jsonSchema, isNotNull);
    });

    test('parses responses with content', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/pets': {
            'get': {
              'operationId': 'listPets',
              'responses': {
                '200': {
                  'description': 'OK',
                  'content': {
                    'application/json': {
                      'schema': {
                        'type': 'array',
                        'items': {'type': 'string'},
                      },
                    },
                  },
                },
                '404': {
                  'description': 'Not found',
                },
              },
            },
          },
        },
      });
      final op = paths.first.operations.first;
      expect(op.responses, hasLength(2));
      expect(op.successResponse, isNotNull);
      expect(op.successResponse!.jsonSchema!.isArray, true);
    });

    test('parses tags', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/pets': {
            'get': {
              'operationId': 'listPets',
              'tags': ['pets', 'admin'],
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      expect(paths.first.operations.first.tags, ['pets', 'admin']);
    });

    test('parses deprecated operation', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/old': {
            'get': {
              'operationId': 'oldEndpoint',
              'deprecated': true,
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      expect(paths.first.operations.first.deprecated, true);
    });

    test('merges path-level and operation-level params', () {
      final paths = pathParser.parsePaths({
        'paths': {
          '/items/{id}': {
            'parameters': [
              {
                'name': 'id',
                'in': 'path',
                'required': true,
                'schema': {'type': 'string'},
              },
            ],
            'get': {
              'operationId': 'getItem',
              'parameters': [
                {
                  'name': 'format',
                  'in': 'query',
                  'schema': {'type': 'string'},
                },
              ],
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      final op = paths.first.operations.first;
      expect(op.parameters, hasLength(2));
    });

    test('warns about unsupported parameter styles', () {
      pathParser.parsePaths({
        'paths': {
          '/test': {
            'get': {
              'operationId': 'test',
              'parameters': [
                {
                  'name': 'ids',
                  'in': 'query',
                  'style': 'pipeDelimited',
                  'schema': {'type': 'array', 'items': {'type': 'string'}},
                },
              ],
              'responses': {
                '200': {'description': 'OK'},
              },
            },
          },
        },
      });
      expect(pathParser.diagnostics, hasLength(1));
      expect(
        pathParser.diagnostics.first.message,
        contains('pipeDelimited'),
      );
    });
  });
}
