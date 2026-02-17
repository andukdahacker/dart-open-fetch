import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('HttpResponse', () {
    test('constructs with required fields', () {
      final response = HttpResponse(statusCode: 200, body: '{"ok":true}');
      expect(response.statusCode, 200);
      expect(response.body, '{"ok":true}');
      expect(response.headers, isEmpty);
    });

    test('constructs with all fields', () {
      final response = HttpResponse(
        statusCode: 200,
        headers: {'Content-Type': 'application/json'},
        body: '{}',
      );
      expect(response.headers, {'Content-Type': 'application/json'});
    });

    test('headers are unmodifiable', () {
      final response = HttpResponse(
        statusCode: 200,
        headers: {'X-Request-Id': 'abc'},
        body: '',
      );
      expect(
        () => response.headers['injected'] = 'value',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('equality with same fields', () {
      final a = HttpResponse(
        statusCode: 200,
        headers: {'X-Id': '1'},
        body: 'hello',
      );
      final b = HttpResponse(
        statusCode: 200,
        headers: {'X-Id': '1'},
        body: 'hello',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different status code', () {
      final a = HttpResponse(statusCode: 200, body: '');
      final b = HttpResponse(statusCode: 404, body: '');
      expect(a, isNot(equals(b)));
    });

    test('toString includes status code', () {
      final response = HttpResponse(statusCode: 200, body: '');
      expect(response.toString(), contains('200'));
    });
  });
}
