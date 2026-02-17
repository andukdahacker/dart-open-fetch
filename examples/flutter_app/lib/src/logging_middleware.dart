import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:flutter/foundation.dart';

/// A [Middleware] that logs HTTP request/response details with timing.
class LoggingMiddleware implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    debugPrint('--> ${request.method} ${request.url}');

    final sw = Stopwatch()..start();
    final response = await next(request);
    sw.stop();

    debugPrint('<-- ${response.statusCode} (${sw.elapsedMilliseconds}ms)');
    return response;
  }
}
