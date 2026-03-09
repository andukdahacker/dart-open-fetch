import 'package:dart_open_fetch_core/src/generator/name_resolver.dart';
import 'package:dart_open_fetch_core/src/generator/wrapper_generator.dart';
import 'package:dart_open_fetch_core/src/ir/api_info.dart';
import 'package:dart_open_fetch_core/src/ir/api_operation.dart';
import 'package:dart_open_fetch_core/src/ir/api_parameter.dart';
import 'package:dart_open_fetch_core/src/ir/api_path.dart';
import 'package:dart_open_fetch_core/src/ir/api_request_body.dart';
import 'package:dart_open_fetch_core/src/ir/api_response.dart';
import 'package:dart_open_fetch_core/src/ir/api_schema.dart';
import 'package:dart_open_fetch_core/src/ir/api_spec.dart';
import 'package:test/test.dart';

void main() {
  late NameResolver nameResolver;
  late WrapperGenerator generator;

  setUp(() {
    nameResolver = NameResolver();
    generator = WrapperGenerator(nameResolver: nameResolver);
  });

  ApiSpec makeSpec({
    String title = 'TestApi',
    String baseUrl = 'https://api.example.com/v1',
    List<ApiPath> paths = const [],
  }) {
    return ApiSpec(
      info: ApiInfo(
        title: title,
        version: '1.0.0',
        servers: [baseUrl],
      ),
      paths: paths,
    );
  }

  group('WrapperGenerator', () {
    test('generates wrapper methods for typed responses', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listPets',
                responses: [
                  ApiResponse(
                    statusCode: '200',
                    content: {
                      'application/json': ApiSchema(
                        type: SchemaType.array,
                        items: ApiSchema(name: 'Pet', type: SchemaType.object),
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final wrappers = generator.generateWrappers(spec);
      expect(wrappers, hasLength(1));
      expect(wrappers.first.className, 'TestApiService');
      final source = wrappers.first.source;
      expect(source, contains('class TestApiService'));
      expect(source, contains('Future<List<Pet>> listPets('));
      expect(source, contains('_client.listPets('));
      expect(source, contains('return response.data'));
    });

    test('forwards parameters correctly', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets/{petId}',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'getPet',
                parameters: [
                  ApiParameter(
                    name: 'petId',
                    location: ParameterLocation.path,
                    schema: ApiSchema(type: SchemaType.string),
                    required_: true,
                  ),
                ],
                responses: [
                  ApiResponse(
                    statusCode: '200',
                    content: {
                      'application/json':
                          ApiSchema(name: 'Pet', type: SchemaType.object),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final wrappers = generator.generateWrappers(spec);
      final source = wrappers.first.source;
      expect(source, contains('required String petId'));
      expect(source, contains('petId: petId'));
    });

    test('skips untyped responses', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/download',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'downloadFile',
                responses: [
                  ApiResponse(
                    statusCode: '200',
                    content: {
                      'application/octet-stream':
                          ApiSchema(type: SchemaType.string),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final wrappers = generator.generateWrappers(spec);
      expect(wrappers, isEmpty);
    });

    test('forwards request body parameter', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'post',
                operationId: 'createPet',
                requestBody: ApiRequestBody(
                  required_: true,
                  content: {
                    'application/json':
                        ApiSchema(name: 'Pet', type: SchemaType.object),
                  },
                ),
                responses: [
                  ApiResponse(
                    statusCode: '201',
                    content: {
                      'application/json':
                          ApiSchema(name: 'Pet', type: SchemaType.object),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final wrappers = generator.generateWrappers(spec);
      final source = wrappers.first.source;
      expect(source, contains('required Pet body'));
      expect(source, contains('body: body'));
    });

    test('groups wrappers by tags', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listPets',
                tags: ['pets'],
                responses: [
                  ApiResponse(
                    statusCode: '200',
                    content: {
                      'application/json': ApiSchema(
                        type: SchemaType.array,
                        items: ApiSchema(name: 'Pet', type: SchemaType.object),
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
          ApiPath(
            path: '/users',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listUsers',
                tags: ['users'],
                responses: [
                  ApiResponse(
                    statusCode: '200',
                    content: {
                      'application/json': ApiSchema(
                        type: SchemaType.array,
                        items: ApiSchema(name: 'User', type: SchemaType.object),
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final wrappers = generator.generateWrappers(spec);
      expect(wrappers, hasLength(2));
      final names = wrappers.map((w) => w.className).toSet();
      expect(names, contains('PetsService'));
      expect(names, contains('UsersService'));
    });
  });
}
