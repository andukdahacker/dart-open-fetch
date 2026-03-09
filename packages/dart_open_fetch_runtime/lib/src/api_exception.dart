/// Exception thrown by generated client methods on non-2xx responses.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.body,
    this.headers = const {},
    this.parsedBody,
  });

  /// HTTP status code.
  final int statusCode;

  /// Raw response body.
  final String body;

  /// Response headers.
  final Map<String, String> headers;

  /// Parsed error body, if the error response has a typed schema.
  final Object? parsedBody;

  /// Returns [parsedBody] cast to [T], or `null` if it is not of that type.
  T? parsedBodyAs<T>() => parsedBody is T ? parsedBody as T : null;

  @override
  String toString() => 'ApiException($statusCode: $body)';
}
