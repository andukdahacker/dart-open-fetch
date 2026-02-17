import 'http_request.dart';
import 'http_response.dart';

/// Callback to the next handler in the middleware chain.
typedef Next = Future<HttpResponse> Function(HttpRequest request);

/// Middleware for composable request/response processing.
///
/// Implement this to add cross-cutting concerns like auth, logging, or retry.
abstract class Middleware {
  /// Handle a request, optionally delegating to [next].
  Future<HttpResponse> handle(HttpRequest request, Next next);
}
