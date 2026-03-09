import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('ApiException', () {
    test('parsedBodyAs returns typed value when type matches', () {
      final exception = ApiException(
        statusCode: 400,
        body: '{"error":"bad"}',
        parsedBody: {'error': 'bad'},
      );
      final result = exception.parsedBodyAs<Map<String, dynamic>>();
      expect(result, isNotNull);
      expect(result!['error'], 'bad');
    });

    test('parsedBodyAs returns null on type mismatch', () {
      final exception = ApiException(
        statusCode: 400,
        body: '{"error":"bad"}',
        parsedBody: 'a string value',
      );
      final result = exception.parsedBodyAs<Map<String, dynamic>>();
      expect(result, isNull);
    });

    test('parsedBodyAs returns null when parsedBody is null', () {
      final exception = ApiException(
        statusCode: 500,
        body: 'Internal Server Error',
      );
      final result = exception.parsedBodyAs<Map<String, dynamic>>();
      expect(result, isNull);
    });

    test('toString includes statusCode and body', () {
      final exception = ApiException(
        statusCode: 404,
        body: 'Not Found',
      );
      expect(exception.toString(), contains('404'));
      expect(exception.toString(), contains('Not Found'));
    });
  });
}
