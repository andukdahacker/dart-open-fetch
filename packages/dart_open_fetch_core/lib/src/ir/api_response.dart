import 'api_schema.dart';

/// A response for an API operation, keyed by status code.
class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    this.description,
    this.content = const {},
    this.headers = const {},
  });

  /// HTTP status code (e.g., '200', '404', 'default').
  final String statusCode;

  /// Response description.
  final String? description;

  /// Content type to schema mapping.
  final Map<String, ApiSchema> content;

  /// Response headers (name → schema).
  final Map<String, ApiSchema> headers;

  /// Get the JSON schema if available.
  ApiSchema? get jsonSchema => content['application/json'];

  @override
  String toString() => 'ApiResponse($statusCode)';
}
