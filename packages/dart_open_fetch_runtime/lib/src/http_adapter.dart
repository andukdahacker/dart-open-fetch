import 'http_request.dart';
import 'http_response.dart';

/// Users implement this to plug in any HTTP library.
abstract class HttpAdapter {
  /// Send an [HttpRequest] and return the [HttpResponse].
  Future<HttpResponse> send(HttpRequest request);
}
