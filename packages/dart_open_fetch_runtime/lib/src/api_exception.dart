/// Exception thrown by generated client methods on non-2xx responses.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  /// HTTP status code.
  final int statusCode;

  /// Raw response body.
  final String body;

  /// Response headers.
  final Map<String, String> headers;

  @override
  String toString() => 'ApiException($statusCode: $body)';
}
