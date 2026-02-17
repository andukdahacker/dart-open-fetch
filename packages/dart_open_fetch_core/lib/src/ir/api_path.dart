import 'api_operation.dart';

/// A URL path with its operations.
class ApiPath {
  const ApiPath({
    required this.path,
    this.operations = const [],
  });

  /// URL path template (e.g., '/users/{id}').
  final String path;

  /// Operations on this path.
  final List<ApiOperation> operations;

  @override
  String toString() => 'ApiPath($path, ${operations.length} ops)';
}
