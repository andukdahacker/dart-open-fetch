import 'http_adapter.dart';
import 'http_request.dart';
import 'http_response.dart';
import 'middleware.dart';

/// Composes a list of [Middleware] with a final [HttpAdapter] into a chain.
///
/// Middleware executes in order: first added = first to handle the request.
/// Responses flow back in reverse order.
class MiddlewareChain {
  MiddlewareChain(this._adapter, [this._middleware = const []]);

  final HttpAdapter _adapter;
  final List<Middleware> _middleware;

  /// Send a request through the middleware chain to the adapter.
  Future<HttpResponse> send(HttpRequest request) {
    // Build the chain from the adapter outward.
    Next chain = _adapter.send;

    // Wrap in reverse so first middleware in list executes first.
    for (var i = _middleware.length - 1; i >= 0; i--) {
      final middleware = _middleware[i];
      final next = chain;
      chain = (req) => middleware.handle(req, next);
    }

    return chain(request);
  }
}
