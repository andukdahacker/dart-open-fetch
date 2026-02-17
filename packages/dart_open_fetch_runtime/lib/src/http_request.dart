import 'package:collection/collection.dart';

/// Immutable HTTP request value class.
///
/// Headers are wrapped in `Map.unmodifiable()` at construction.
/// Middleware that needs to modify headers must create a new [HttpRequest].
class HttpRequest {
  HttpRequest({
    required this.method,
    required this.url,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  /// HTTP method: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS.
  final String method;

  /// Fully constructed URL including query params.
  final Uri url;

  /// Unmodifiable headers map.
  final Map<String, String> headers;

  /// Request body — null (no body) or JSON-serialized string.
  final String? body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpRequest &&
          method == other.method &&
          url == other.url &&
          const MapEquality<String, String>()
              .equals(headers, other.headers) &&
          body == other.body;

  @override
  int get hashCode => Object.hash(
        method,
        url,
        const MapEquality<String, String>().hash(headers),
        body,
      );

  @override
  String toString() => 'HttpRequest($method $url)';
}
