import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('HttpRequest', () {
    test('constructs with required fields', () {
      final request = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      );
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://example.com/api'));
      expect(request.headers, isEmpty);
      expect(request.body, isNull);
    });

    test('constructs with all fields', () {
      final request = HttpRequest(
        method: 'POST',
        url: Uri.parse('https://example.com/api'),
        headers: {'Content-Type': 'application/json'},
        body: '{"name":"test"}',
      );
      expect(request.method, 'POST');
      expect(request.headers, {'Content-Type': 'application/json'});
      expect(request.body, '{"name":"test"}');
    });

    test('headers are unmodifiable', () {
      final request = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
        headers: {'Accept': 'application/json'},
      );
      expect(
        () => request.headers['injected'] = 'value',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('equality with same fields', () {
      final a = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
        headers: {'Accept': 'application/json'},
      );
      final b = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
        headers: {'Accept': 'application/json'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different fields', () {
      final a = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
      );
      final b = HttpRequest(
        method: 'POST',
        url: Uri.parse('https://example.com'),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes method and url', () {
      final request = HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      );
      expect(request.toString(), contains('GET'));
      expect(request.toString(), contains('https://example.com/api'));
    });

    group('copyWith', () {
      test('returns identical copy when no args provided', () {
        final original = HttpRequest(
          method: 'POST',
          url: Uri.parse('https://example.com/api'),
          headers: {'Accept': 'application/json'},
          body: '{"a":1}',
        );
        final copy = original.copyWith();
        expect(copy, equals(original));
      });

      test('overrides a single field', () {
        final original = HttpRequest(
          method: 'GET',
          url: Uri.parse('https://example.com/api'),
          headers: {'Accept': 'application/json'},
        );
        final copy = original.copyWith(method: 'POST');
        expect(copy.method, 'POST');
        expect(copy.url, original.url);
        expect(copy.headers, original.headers);
        expect(copy.body, isNull);
      });

      test('headers on copy remain unmodifiable', () {
        final original = HttpRequest(
          method: 'GET',
          url: Uri.parse('https://example.com'),
        );
        final copy = original.copyWith(
          headers: {'X-New': 'value'},
        );
        expect(
          () => copy.headers['injected'] = 'fail',
          throwsA(isA<UnsupportedError>()),
        );
      });
    });
  });
}
