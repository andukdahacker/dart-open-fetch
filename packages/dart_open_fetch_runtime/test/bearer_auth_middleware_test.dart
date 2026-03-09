import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:test/test.dart';

class _MockAdapter implements HttpAdapter {
  final List<HttpRequest> calls = [];

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    calls.add(request);
    return HttpResponse(statusCode: 200, body: 'OK');
  }
}

void main() {
  group('BearerAuthMiddleware', () {
    test('injects Authorization header', () async {
      final adapter = _MockAdapter();
      final middleware = BearerAuthMiddleware('my-token');
      final chain = MiddlewareChain(adapter, [middleware]);

      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      ));

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first.headers['Authorization'], 'Bearer my-token');
    });

    test('preserves existing headers', () async {
      final adapter = _MockAdapter();
      final middleware = BearerAuthMiddleware('token');
      final chain = MiddlewareChain(adapter, [middleware]);

      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
        headers: {'Accept': 'application/json'},
      ));

      expect(adapter.calls.first.headers['Accept'], 'application/json');
      expect(adapter.calls.first.headers['Authorization'], 'Bearer token');
    });

    test('token update works', () async {
      final adapter = _MockAdapter();
      final middleware = BearerAuthMiddleware('old-token');
      final chain = MiddlewareChain(adapter, [middleware]);

      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      ));
      expect(adapter.calls[0].headers['Authorization'], 'Bearer old-token');

      middleware.token = 'new-token';
      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      ));
      expect(adapter.calls[1].headers['Authorization'], 'Bearer new-token');
    });
  });
}
