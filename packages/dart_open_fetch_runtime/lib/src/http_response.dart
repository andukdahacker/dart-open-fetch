import 'package:collection/collection.dart';

/// Immutable HTTP response value class.
///
/// Headers are wrapped in `Map.unmodifiable()` at construction.
class HttpResponse {
  HttpResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    required this.body,
  }) : headers = Map.unmodifiable(headers);

  /// HTTP status code.
  final int statusCode;

  /// Unmodifiable headers map.
  final Map<String, String> headers;

  /// Response body as string (adapters decode bytes).
  final String body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpResponse &&
          statusCode == other.statusCode &&
          const MapEquality<String, String>().equals(headers, other.headers) &&
          body == other.body;

  @override
  int get hashCode => Object.hash(
        statusCode,
        const MapEquality<String, String>().hash(headers),
        body,
      );

  @override
  String toString() => 'HttpResponse($statusCode)';
}
