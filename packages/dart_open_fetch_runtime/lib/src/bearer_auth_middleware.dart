import 'http_request.dart';
import 'http_response.dart';
import 'middleware.dart';

/// Middleware that injects a `Bearer` token into the `Authorization` header.
///
/// The [token] field is mutable so it can be updated (e.g. after a refresh)
/// without creating a new middleware instance.
class BearerAuthMiddleware implements Middleware {
  BearerAuthMiddleware(this.token);

  /// The bearer token. Update this to change the token for future requests.
  String token;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    return next(request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer $token'},
    ));
  }
}
