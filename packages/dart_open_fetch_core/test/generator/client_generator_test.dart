import 'package:dart_open_fetch_core/src/generator/client_generator.dart';
import 'package:dart_open_fetch_core/src/generator/name_resolver.dart';
import 'package:dart_open_fetch_core/src/generator/parameter_serializer.dart';
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
  late ParameterSerializer paramSerializer;
  late ClientGenerator generator;

  setUp(() {
    nameResolver = NameResolver();
    paramSerializer = ParameterSerializer(nameResolver: nameResolver);
    generator = ClientGenerator(
      nameResolver: nameResolver,
      parameterSerializer: paramSerializer,
    );
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

  group('ClientGenerator', () {
    test('generates a simple GET method', () {
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

      final clients = generator.generateClients(spec);
      expect(clients, hasLength(1));
      final source = clients.first.source;
      expect(source, contains('class TestApiClient'));
      expect(source, contains('Future<ApiResponse<List<Pet>>> listPets('));
      expect(source, contains("method: 'GET'"));
      expect(source, contains('_chain.send(request)'));
    });

    test('generates POST method with request body', () {
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

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains('required Pet body'));
      expect(source, contains("'Content-Type': 'application/json'"));
      expect(source, contains('jsonEncode(body.toJson())'));
    });

    test('generates method with path parameters', () {
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

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains('required String petId'));
      expect(source, contains('Uri.encodeComponent'));
    });

    test('generates method with query parameters', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listPets',
                parameters: [
                  ApiParameter(
                    name: 'limit',
                    location: ParameterLocation.query,
                    schema: ApiSchema(type: SchemaType.integer),
                    required_: false,
                  ),
                  ApiParameter(
                    name: 'status',
                    location: ParameterLocation.query,
                    schema: ApiSchema(type: SchemaType.string),
                    required_: true,
                  ),
                ],
                responses: [
                  ApiResponse(statusCode: '200'),
                ],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains('int? limit'));
      expect(source, contains('required String status'));
      expect(source, contains('queryParams'));
    });

    test('groups operations by tags', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listPets',
                tags: ['pets'],
                responses: [ApiResponse(statusCode: '200')],
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
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      expect(clients, hasLength(2));
      final names = clients.map((c) => c.className).toSet();
      expect(names, contains('PetsClient'));
      expect(names, contains('UsersClient'));
    });

    test('operations with no tags go to DefaultClient', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'listPets',
                tags: ['pets'],
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
          ApiPath(
            path: '/health',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'healthCheck',
                tags: [],
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      final names = clients.map((c) => c.className).toSet();
      expect(names, contains('PetsClient'));
      expect(names, contains('DefaultClient'));
    });

    test('multi-tag operations go to first tag only', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/admin/pets',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'adminListPets',
                tags: ['pets', 'admin'],
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      expect(clients, hasLength(1));
      expect(clients.first.className, 'PetsClient');
      expect(clients.first.source, contains('adminListPets'));
    });

    test('generates deprecated annotation on methods', () {
      final spec = makeSpec(
        paths: [
          ApiPath(
            path: '/old',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'oldEndpoint',
                deprecated: true,
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains("@Deprecated('Deprecated in API spec')"));
    });

    test('handles response with no JSON content type', () {
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

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains('Future<HttpResponse> downloadFile'));
      expect(source, contains('return response'));
    });

    test('constructor includes baseUrl with default from spec', () {
      final spec = makeSpec(
        baseUrl: 'https://petstore.swagger.io/v2',
        paths: [
          ApiPath(
            path: '/test',
            operations: [
              ApiOperation(
                method: 'get',
                operationId: 'test',
                responses: [ApiResponse(statusCode: '200')],
              ),
            ],
          ),
        ],
      );

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains("this.baseUrl = 'https://petstore.swagger.io/v2'"));
      expect(source, contains('required HttpAdapter adapter'));
      expect(source, contains('MiddlewareChain(adapter, middleware)'));
    });

    test('throws ApiException for non-2xx responses', () {
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

      final clients = generator.generateClients(spec);
      final source = clients.first.source;
      expect(source, contains('throw ApiException('));
      expect(source, contains('statusCode: response.statusCode'));
    });
  });
}
