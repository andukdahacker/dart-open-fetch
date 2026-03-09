import 'dart:convert';

import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('HttpClientAdapter', () {
    test('sends request and returns response', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('https://example.com/api'));
        return http.Response(
          jsonEncode({'hello': 'world'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final adapter = HttpClientAdapter(client: mockClient);
      final response = await adapter.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
      ));

      expect(response.statusCode, 200);
      expect(response.body, contains('hello'));
      expect(response.headers['content-type'], 'application/json');
    });

    test('sends request body', () async {
      final mockClient = MockClient((request) async {
        expect(request.body, '{"name":"test"}');
        expect(request.headers['Content-Type'], contains('application/json'));
        return http.Response('OK', 201);
      });

      final adapter = HttpClientAdapter(client: mockClient);
      final response = await adapter.send(HttpRequest(
        method: 'POST',
        url: Uri.parse('https://example.com/api'),
        headers: {'Content-Type': 'application/json'},
        body: '{"name":"test"}',
      ));

      expect(response.statusCode, 201);
    });

    test('sends custom headers', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['X-Custom'], 'value');
        return http.Response('OK', 200);
      });

      final adapter = HttpClientAdapter(client: mockClient);
      await adapter.send(HttpRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/api'),
        headers: {'X-Custom': 'value'},
      ));
    });
  });
}
