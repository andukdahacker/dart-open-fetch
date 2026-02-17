/// Base class for all dart_open_fetch fatal errors.
class OpenFetchException implements Exception {
  const OpenFetchException(this.message, {this.schemaPath});

  /// Human-readable error message.
  final String message;

  /// JSON pointer to the location in the schema (e.g., `#/paths/~1users/get`).
  final String? schemaPath;

  @override
  String toString() {
    final location = schemaPath != null ? ' at $schemaPath' : '';
    return '$runtimeType: $message$location';
  }
}

/// Schema is structurally invalid or uses unsupported version.
class SchemaParseException extends OpenFetchException {
  const SchemaParseException(super.message, {super.schemaPath});
}

/// `$ref` target not found or circular ref detected.
class RefResolutionException extends OpenFetchException {
  const RefResolutionException(super.message, {super.schemaPath});
}

/// Code generation failed for a specific schema/operation.
class GenerationException extends OpenFetchException {
  const GenerationException(super.message, {super.schemaPath});
}
