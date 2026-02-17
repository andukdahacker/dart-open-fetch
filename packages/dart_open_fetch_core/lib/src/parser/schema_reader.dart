import '../errors.dart';

/// Validates a pre-parsed schema map has the correct structure.
class SchemaReader {
  /// Validate the raw map is an OpenAPI schema. Returns the validated map.
  Map<String, dynamic> validate(Map<String, dynamic> raw) {
    // Check for Swagger 2.0
    if (raw.containsKey('swagger')) {
      throw const SchemaParseException(
        'Swagger 2.0 is not supported. Please convert to OpenAPI 3.0+ '
        'using https://converter.swagger.io',
      );
    }

    // Check for openapi field
    if (!raw.containsKey('openapi')) {
      throw const SchemaParseException(
        'Missing required "openapi" field. This does not appear to be '
        'a valid OpenAPI 3.x schema.',
      );
    }

    final version = raw['openapi'];
    if (version is! String) {
      throw const SchemaParseException(
        'The "openapi" field must be a string (e.g., "3.0.3" or "3.1.0").',
      );
    }

    if (!version.startsWith('3.')) {
      throw SchemaParseException(
        'Unsupported OpenAPI version: $version. Only 3.0.x and 3.1.x are supported.',
      );
    }

    return raw;
  }
}
