import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';

/// A [Middleware] that logs HTTP request/response details with timing.
class LoggingMiddleware implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    print('--> ${request.method} ${request.url}');

    final sw = Stopwatch()..start();
    final response = await next(request);
    sw.stop();

    print('<-- ${response.statusCode} (${sw.elapsedMilliseconds}ms)');
    return response;
  }
}
