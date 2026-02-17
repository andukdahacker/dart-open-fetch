import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:test/test.dart';

/// Mock adapter that records calls and returns a fixed response.
class MockAdapter implements HttpAdapter {
  final List<HttpRequest> calls = [];
  final HttpResponse response;

  MockAdapter([HttpResponse? response])
      : response =
            response ?? HttpResponse(statusCode: 200, body: '{"mock":true}');

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    calls.add(request);
    return response;
  }
}

/// Test middleware that appends a header and records execution order.
class HeaderMiddleware implements Middleware {
  HeaderMiddleware(this.headerName, this.headerValue, {this.log});

  final String headerName;
  final String headerValue;
  final List<String>? log;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    log?.add('$headerName-before');
    final newHeaders = Map<String, String>.from(request.headers);
    newHeaders[headerName] = headerValue;
    final modifiedRequest = HttpRequest(
      method: request.method,
      url: request.url,
      headers: newHeaders,
      body: request.body,
    );
    final response = await next(modifiedRequest);
    log?.add('$headerName-after');
    return response;
  }
}

/// Middleware that short-circuits without calling next.
class ShortCircuitMiddleware implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    return HttpResponse(statusCode: 403, body: 'Forbidden');
  }
}

void main() {
  group('MiddlewareChain', () {
    test('empty middleware list goes directly to adapter', () async {
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter);
      final request = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      );

      final response = await chain.send(request);

      expect(response.statusCode, 200);
      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first, equals(request));
    });

    test('single middleware wraps adapter', () async {
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter, [
        HeaderMiddleware('X-Auth', 'token123'),
      ]);
      final request = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      );

      await chain.send(request);

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first.headers['X-Auth'], 'token123');
    });

    test('middleware executes in order (first added = first to handle)',
        () async {
      final log = <String>[];
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter, [
        HeaderMiddleware('A', '1', log: log),
        HeaderMiddleware('B', '2', log: log),
      ]);

      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      ));

      // A handles first, then B, then adapter. Response returns through B then A.
      expect(log, ['A-before', 'B-before', 'B-after', 'A-after']);
    });

    test('middleware can modify request headers (copy-on-write)', () async {
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter, [
        HeaderMiddleware('X-First', 'one'),
        HeaderMiddleware('X-Second', 'two'),
      ]);

      await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      ));

      // Adapter receives request with both headers
      expect(adapter.calls.first.headers['X-First'], 'one');
      expect(adapter.calls.first.headers['X-Second'], 'two');
    });

    test('middleware can short-circuit without calling next', () async {
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter, [
        ShortCircuitMiddleware(),
      ]);

      final response = await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      ));

      expect(response.statusCode, 403);
      expect(response.body, 'Forbidden');
      expect(adapter.calls, isEmpty);
    });

    test('middleware after short-circuit is not reached', () async {
      final log = <String>[];
      final adapter = MockAdapter();
      final chain = MiddlewareChain(adapter, [
        HeaderMiddleware('A', '1', log: log),
        ShortCircuitMiddleware(),
        HeaderMiddleware('B', '2', log: log),
      ]);

      final response = await chain.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      ));

      // A runs before, short-circuit happens, B never runs, A runs after
      expect(log, ['A-before', 'A-after']);
      expect(response.statusCode, 403);
      expect(adapter.calls, isEmpty);
    });
  });
}
