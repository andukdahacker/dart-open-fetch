import 'api_info.dart';
import 'api_path.dart';
import 'api_schema.dart';
import 'api_security.dart';

/// Root IR node representing a complete parsed OpenAPI specification.
class ApiSpec {
  const ApiSpec({
    required this.info,
    this.paths = const [],
    this.schemas = const [],
    this.securitySchemes = const [],
  });

  /// API metadata (title, version, servers).
  final ApiInfo info;

  /// All API paths with their operations.
  final List<ApiPath> paths;

  /// All component schemas (named types).
  final List<ApiSchema> schemas;

  /// Security scheme definitions.
  final List<ApiSecurityScheme> securitySchemes;

  @override
  String toString() =>
      'ApiSpec(${info.title}, ${paths.length} paths, ${schemas.length} schemas)';
}
