import 'api_schema.dart';

/// A request body for an API operation.
class ApiRequestBody {
  const ApiRequestBody({
    this.required_ = false,
    this.content = const {},
    this.description,
  });

  /// Whether the request body is required.
  final bool required_;

  /// Content type to schema mapping (e.g., 'application/json' → ApiSchema).
  final Map<String, ApiSchema> content;

  /// Description.
  final String? description;

  /// Get the JSON schema if available.
  ApiSchema? get jsonSchema => content['application/json'];

  @override
  String toString() =>
      'ApiRequestBody(${content.keys.join(', ')}, required: $required_)';
}
