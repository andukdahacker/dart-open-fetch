/// Typed success response wrapper returned by generated client methods.
class ApiResponse<T> {
  const ApiResponse({
    required this.data,
    required this.statusCode,
    this.headers = const {},
  });

  /// Deserialized response body.
  final T data;

  /// HTTP status code.
  final int statusCode;

  /// Response headers.
  final Map<String, String> headers;

  @override
  String toString() => 'ApiResponse<$T>($statusCode)';
}
